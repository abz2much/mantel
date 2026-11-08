import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class NotchState: ObservableObject {
    /// What the expanded notch shows: a meeting reminder, the hover panel with its tabs, or "Time's up".
    /// (`.music`, the music card on its own, is no longer used now the peek is gone.)
    enum Content { case meeting, music, panel, timerDone }

    @Published var event: MeetingEvent?
    @Published var content: Content = .music
    /// The hover panel's open tab; whichever was shown last opens next time.
    @Published var tab: HoverTab = .music {
        didSet { lastTab = tab }
    }
    private(set) var lastTab: HoverTab?
    /// The battery flash showing in the compact notch, if any, and when it started.
    @Published var battery: BatteryAlert?
    @Published var batteryShownAt: Date?
    /// True while typing a new reminder: the panel stays open until done.
    @Published var typing = false
    /// The highlighted clipboard row while the panel was opened with ⌃⌥V; nil otherwise.
    @Published var clipboardSelection: Int?
}

/// Runs one notch per screen. Decides what each shows (alerts on the active app's screen only; otherwise
/// the notch's side pieces, or a monitor's tab) and drives them.
@MainActor
final class NotchController {
    private static let batteryFlashDuration: TimeInterval = 3

    private static let log = Logger(subsystem: "local.notch.app", category: "notch")

    private typealias NotchScreenPresenter = NotchPresenter<NotchRootView, CompactLeading, CompactTrailing>
    private typealias MonitorPresenter = NotchPresenter<NotchRootView, MonitorTabView, EmptyView>

    private let calendar: CalendarService
    private let reminders: RemindersService
    private let music: MusicService
    private let battery: BatteryService
    private let clipboard: ClipboardService
    private let timerService: TimerService
    private let monitors: MonitorSettings
    private let state = NotchState()

    private var stages: [Int: NotchStage] = [:]
    private var dismissed: Set<ReminderKey> = []
    private var currentReminder: ReminderKey?

    private var glowCancellable: AnyCancellable?
    private var monitorsCancellable: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var pointer: PointerWatcher?
    private var timer: Timer?
    private var batteryTimer: Timer?
    private var hotKey: GlobalHotKey?
    private var registeredShortcut: Shortcut?
    private var clipboardCancellable: AnyCancellable?
    private var typingCancellable: AnyCancellable?
    private var typingResign: NSObjectProtocol?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(calendar: CalendarService, reminders: RemindersService, music: MusicService, battery: BatteryService, clipboard: ClipboardService, timer: TimerService,
         monitors: MonitorSettings) {
        self.calendar = calendar
        self.reminders = reminders
        self.music = music
        self.battery = battery
        self.clipboard = clipboard
        self.timerService = timer
        self.monitors = monitors
        timer.onChange = { [weak self] in
            guard let self else { return }
            evaluate()
            // Hover was ignored while "Time's up" showed; if the pointer is still there, open the panel.
            if !timerService.doneShowing { stages.values.forEach { $0.recheckHover() } }
        }
        battery.onAlert = { [weak self] alert in self?.flashBattery(alert) }
        calendar.onUpdate = { [weak self] in self?.evaluate() }
        music.onChange = { [weak self] in self?.evaluate() }
    }

    func start() {
        rebuildStages()

        // Plugging in a monitor, closing the lid or changing resolution: one stage per screen, then re-decide.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildStages()
                self?.evaluate()
            }
        }

        // Keeps the glow around each shape in step with the open tab and the album, which the views don't watch.
        glowCancellable = Publishers.CombineLatest3(state.$content, state.$tab, music.objectWillChange.prepend(()))
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                MainActor.assumeIsolated { self?.updateGlow() }
            }

        monitorsCancellable = monitors.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }

        // The shortcut (⌃⌥V unless changed) opens the clipboard panel; registered only while the setting is on.
        clipboardCancellable = clipboard.objectWillChange.prepend(())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateHotKey() }
            }

        // Typing a reminder keeps the panel open; finishing hands the keyboard back.
        typingCancellable = state.$typing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] typing in
                MainActor.assumeIsolated { self?.typingChanged(typing) }
            }

        // Hover and click-through follow the pointer position.
        pointer = PointerWatcher { [weak self] point in self?.pointerMoved(point) }
        pointer?.start()

        // Local tick only: starts/ends the meeting popup at the right second.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerService.checkFinished()   // catches a countdown that ended while the Mac slept
                self?.evaluate()
            }
        }
        evaluate()
    }

    // MARK: Screens

    /// Which stages to add and which to drop, given the screens now attached.
    nonisolated static func stageIDs(for screens: [ScreenInfo], current: [Int]) -> (add: [Int], remove: [Int]) {
        let now = Set(screens.map(\.id))
        return (add: screens.map(\.id).filter { !current.contains($0) },
                remove: current.filter { !now.contains($0) }.sorted())
    }

    private static func screenInfos() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in
            screen.screenNumber.map {
                ScreenInfo(id: $0.intValue, hasNotch: screen.notchMetrics.hasNotch, isMain: screen == NSScreen.screens.first)
            }
        }
    }

    private static func screen(for id: Int) -> NSScreen? {
        NSScreen.screens.first { $0.screenNumber?.intValue == id }
    }

    private func rebuildStages() {
        let infos = Self.screenInfos()
        let diff = Self.stageIDs(for: infos, current: Array(stages.keys))
        for id in diff.remove {
            // The shortcut panel was on that screen: finish it properly, so no key listener is left behind.
            if stages[id]?.pinned == true {
                if pinOwner == .clipboard { closeClipboard() } else { pinOwner = nil }
            }
            stages.removeValue(forKey: id)?.tearDown()
        }
        for info in infos where diff.add.contains(info.id) {
            stages[info.id] = makeStage(info)
        }
        updateGlow()
    }

    private func makeStage(_ info: ScreenInfo) -> NotchStage {
        let flags = StageFlags()
        let presenter: NotchPresenting
        if info.hasNotch {
            presenter = NotchScreenPresenter(
                expanded: { [unowned self] in rootView() },
                leading: { [unowned self] in CompactLeading(state: state, music: music, timer: timerService, flags: flags) },
                trailing: { [unowned self] in CompactTrailing(state: state, music: music, timer: timerService, flags: flags) }
            )
        } else {
            presenter = MonitorPresenter(
                expanded: { [unowned self] in rootView() },
                leading: { [unowned self] in MonitorTabView(state: state, music: music, timer: timerService, flags: flags) },
                trailing: { EmptyView() }
            )
        }
        let id = info.id
        let stage = NotchStage(screenID: id, presenter: presenter, flags: flags) { [weak self] expanded in
            self?.hoverExpandedChanged(on: id, expanded: expanded)
        }
        return stage
    }

    private func rootView() -> NotchRootView {
        NotchRootView(
            state: state,
            music: music,
            calendar: calendar,
            reminders: reminders,
            clipboard: clipboard,
            timer: timerService,
            onJoin: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.dismissCurrent()
            },
            onDismiss: { [weak self] in self?.dismissCurrent() }
        )
    }

    private func updateGlow() {
        let colour = NotchDecision.glowColor(content: state.content, tab: state.tab, accent: music.accent)
        for stage in stages.values where stage.presenter.glowColor != colour {
            stage.presenter.glowColor = colour
        }
    }

    // MARK: Hover

    private func pointerMoved(_ point: CGPoint) {
        for stage in stages.values {
            let zone: CGRect?
            if let screen = Self.screen(for: stage.screenID), !screen.notchMetrics.hasNotch, monitors.enabled {
                zone = NotchGeometry.hoverZone(screenFrame: screen.frame)
            } else {
                zone = nil
            }
            stage.pointerMoved(to: point, zone: zone)
        }
    }

    /// Only one panel is ever open: opening one closes any other.
    private func hoverExpandedChanged(on id: Int, expanded: Bool) {
        Self.log.info("hover \(expanded, privacy: .public) on \(id, privacy: .public)")
        if expanded {
            state.tab = HoverTab.opening(last: state.lastTab, hasTrack: music.track != nil)
            for stage in stages.values where stage.screenID != id { stage.hoverExpanded = false }
        }
        evaluate()
    }

    // MARK: Clipboard shortcut

    /// Registers the chosen shortcut, re-registering when it changes; tells Settings if another app owns it.
    private func updateHotKey() {
        guard clipboard.opensWithShortcut else {
            hotKey?.unregister()
            hotKey = nil
            registeredShortcut = nil
            closeClipboard()
            if clipboard.shortcutTaken { clipboard.shortcutTaken = false }
            return
        }
        guard registeredShortcut != clipboard.shortcut || hotKey?.isRegistered != true else { return }
        hotKey?.unregister()
        let key = GlobalHotKey(clipboard.shortcut) { [weak self] in self?.toggleClipboard() }
        // If another app owns it, this is tried again on every clipboard change, so it starts working once freed.
        key.register()
        hotKey = key
        registeredShortcut = clipboard.shortcut
        if clipboard.shortcutTaken != !key.isRegistered { clipboard.shortcutTaken = !key.isRegistered }
    }

    private var pinnedStage: NotchStage? { stages.values.first { $0.pinned } }

    /// What pinned the panel open: the clipboard shortcut (with its own keys), or typing a reminder.
    private enum PinOwner { case clipboard, typing }
    private var pinOwner: PinOwner?

    /// ⌃⌥V: opens the panel on the Clipboard tab on the active app's screen, or closes it if open.
    private func toggleClipboard() {
        if pinOwner == .clipboard { closeClipboard(); return }
        // Typing a reminder: switch the open panel to the clipboard rather than closing it.
        if pinOwner == .typing, let stage = pinnedStage {
            pinOwner = .clipboard
            state.tab = .clipboard
            state.clipboardSelection = 0
            startKeyboard()
            if let window = stage.presenter.window { takeKeyboard(window) }
            return
        }
        let infos = Self.screenInfos()
        guard let id = NotchDecision.alertScreen(screens: infos, active: ActiveScreen.current(), monitorsEnabled: monitors.enabled),
              let stage = stages[id] else { return }
        for other in stages.values where other !== stage { other.hoverExpanded = false }
        state.tab = .clipboard
        state.clipboardSelection = 0
        stage.pin()
        pinOwner = .clipboard
        evaluate()
        // A meeting or "Time's up" has the panel; the shortcut does nothing then.
        guard stage.hoverExpanded else { stage.unpin(); state.clipboardSelection = nil; return }
        startKeyboard()
        // Already open from hovering: nothing new to show, so take the keyboard now.
        if stage.applied == stage.desired, [.musicExpanded, .idleExpanded].contains(stage.applied),
           let window = stage.presenter.window {
            takeKeyboard(window)
        }
    }

    /// Listens for ↑ ↓ Return 1–9 Esc while the pinned panel has the keyboard.
    private func startKeyboard() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) == true ? nil : event }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard pinOwner == .clipboard,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = ClipboardKeys.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) else { return false }
        let items = clipboard.enabled ? clipboard.items : []
        switch ClipboardKeys.handle(key, selection: state.clipboardSelection ?? 0, count: items.count,
                                    onClipboardTab: state.tab == .clipboard) {
        case .select(let row): state.clipboardSelection = row
        case .copy(let row):
            clipboard.copy(items[row])
            closeClipboard()
        case .close: closeClipboard()
        case .pass: return false
        }
        return true
    }

    /// Takes the keyboard once the pinned panel is on screen, and closes if the user clicks elsewhere.
    private func takeKeyboard(_ window: NSPanel) {
        window.makeKey()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeClipboard() }
        }
    }

    private func closeClipboard() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        state.clipboardSelection = nil
        guard pinOwner == .clipboard, let stage = pinnedStage else { return }
        pinOwner = nil
        stage.unpin()
        // Hand the keyboard back to the app in front, so ⌘V pastes there.
        handBackKeyboard(stage)
        evaluate()
        stage.recheckHover()
    }

    // MARK: Typing a reminder

    private func typingChanged(_ typing: Bool) {
        if let typingResign { NotificationCenter.default.removeObserver(typingResign) }
        typingResign = nil
        if typing {
            guard pinOwner == nil, let stage = stages.values.first(where: { $0.hoverExpanded && !$0.pinned }) else { return }
            stage.pin()
            pinOwner = .typing
            stage.presenter.window?.makeKey()   // backstop: the text field needs the keyboard
            // Clicking another app ends typing, so the panel doesn't stay pinned open.
            typingResign = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: stage.presenter.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.typing = false }
            }
        } else if pinOwner == .typing, let stage = pinnedStage {
            pinOwner = nil
            stage.unpin(stayOpenIfHovered: true)
            if !stage.hoverExpanded { handBackKeyboard(stage) }
            evaluate()
        }
    }

    /// Lets the app in front have the keyboard again, so ⌘V and typing go there.
    private func handBackKeyboard(_ stage: NotchStage) {
        if let window = stage.presenter.window, window.isKeyWindow {
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
    }

    // MARK: Battery

    /// Shows the battery flash for a few seconds on the alert screen, then puts back what was there.
    private func flashBattery(_ alert: BatteryAlert) {
        let infos = Self.screenInfos()
        guard let id = NotchDecision.alertScreen(screens: infos, active: ActiveScreen.current(), monitorsEnabled: monitors.enabled),
              let info = infos.first(where: { $0.id == id }), info.hasNotch || monitors.enabled else { return }
        state.battery = alert
        if stages[id]?.applied == .battery {
            startFlashClock()   // already showing: a new alert restarts the flash
        } else {
            state.batteryShownAt = nil   // the clock starts once the compact view is showing
            evaluate()
        }
    }

    /// Starts the sweep and the 3 s countdown. Called once the compact view is on screen,
    /// so shrinking from an expanded card first doesn't eat the start of the sweep.
    private func startFlashClock() {
        state.batteryShownAt = Date()
        batteryTimer?.invalidate()
        let timer = Timer(timeInterval: Self.batteryFlashDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endFlash() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps time while the menu bar menu is open
        batteryTimer = timer
    }

    private func endFlash() {
        state.battery = nil
        state.batteryShownAt = nil
        evaluate()
        // Hover was ignored during the flash; if the pointer is still there, open the panel now.
        stages.values.forEach { $0.recheckHover() }
    }

    private func dismissCurrent() {
        if let key = currentReminder { dismissed.insert(key) }
        evaluate()
    }

    // MARK: Decide

    private func evaluate() {
        let now = Date()
        let target = ReminderPicker.pick(calendar.events, now: now, dismissed: dismissed)
        dismissed = dismissed.filter { key in calendar.events.contains { $0.id == key.eventID } }
        if let target {
            state.event = target.event   // keeps title/link fresh after refetches
            currentReminder = target.key
        } else {
            currentReminder = nil
        }

        let infos = Self.screenInfos()
        let alertID = NotchDecision.alertScreen(screens: infos, active: ActiveScreen.current(), monitorsEnabled: monitors.enabled)
        let anyNotch = infos.contains(where: \.hasNotch)
        for info in infos {
            guard let stage = stages[info.id] else { continue }
            var inputs = NotchInputs(
                hasReminder: target != nil,
                musicShowsCard: music.showsCard,
                screenHasNotch: info.hasNotch,
                hoverExpanded: stage.hoverExpanded,
                isAlertScreen: info.id == alertID,
                timerDoneShowing: timerService.doneShowing,
                batteryFlashing: state.battery != nil,
                timerRunning: timerService.countdown.isActive,
                monitorsEnabled: monitors.enabled,
                tabEnabled: monitors.tabEnabled,
                anyNotchScreen: anyNotch
            )
            stage.hoverExpanded = NotchDecision.keepsHoverExpanded(inputs)
            inputs.hoverExpanded = stage.hoverExpanded
            let mode = NotchDecision.mode(for: inputs)
            stage.apply(mode) { [weak self, weak stage] mode in
                guard let self, let stage else { return }
                await perform(mode, on: stage)
            }
        }
        // A meeting or "Time's up" took the panel: the shortcut panel is over.
        if let pinned = pinnedStage, !pinned.hoverExpanded {
            if pinOwner == .clipboard {
                closeClipboard()
            } else {
                pinned.unpin()
                pinOwner = nil
            }
        }
    }

    private func perform(_ mode: NotchMode, on stage: NotchStage) async {
        Self.log.info("screen \(stage.screenID, privacy: .public) mode -> \(String(describing: mode), privacy: .public)")
        // The music tab's progress bar needs the position; any open panel can show it.
        music.setPolling(stages.values.contains { [.musicExpanded, .idleExpanded].contains($0.applied) })
        stage.flags.showsBattery = mode == .battery
        guard let screen = Self.screen(for: stage.screenID) else { return }
        switch mode {
        case .hidden: await stage.presenter.hide()
        case .musicCompact, .idle, .tab:
            await stage.presenter.compact(on: screen)
            // The panel closed while it had the keyboard (after typing): give it back.
            if !stage.pinned, stage.presenter.window?.isKeyWindow == true { handBackKeyboard(stage) }
        case .battery:
            await stage.presenter.compact(on: screen)
            if stage.desired == .battery { startFlashClock() }
        case .musicExpanded, .idleExpanded:
            state.content = .panel
            await stage.presenter.expand(on: screen)
            if pinOwner == .clipboard, stage.pinned, stage.desired == mode, let window = stage.presenter.window {
                takeKeyboard(window)
            }
        case .meeting:
            state.content = .meeting
            await stage.presenter.expand(on: screen)
        case .timerDone:
            state.content = .timerDone
            await stage.presenter.expand(on: screen)
            timerService.doneAppeared()   // its 10 seconds start now it's actually on screen
        }
    }
}
