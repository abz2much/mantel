import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class NotchState: ObservableObject {
    /// What the expanded notch shows: a meeting reminder, the music card on its own (a peek on
    /// screens without a notch), or the hover panel with its tabs.
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
}

/// Decides what the notch shows (battery flash > meeting > "Time's up" > music > idle) and drives it.
@MainActor
final class NotchController {
    private static let hoverDwell: TimeInterval = 0.3
    private static let hoverLeaveDelay: TimeInterval = 0.5
    private static let peekDuration: TimeInterval = 6
    private static let batteryFlashDuration: TimeInterval = 3

    private static let log = Logger(subsystem: "local.notch.app", category: "notch")

    private let calendar: CalendarService
    private let music: MusicService
    private let battery: BatteryService
    private let clipboard: ClipboardService
    private let timerService: TimerService
    private let state = NotchState()
    private var notch: NotchPresenter<NotchRootView, CompactLeading, CompactTrailing>?

    private var dismissed: Set<ReminderKey> = []
    private var currentReminder: ReminderKey?

    private var desired: NotchMode = .hidden
    private var applied: NotchMode = .hidden
    private var reconciling = false

    private var hoverExpanded = false
    private var hoverTimer: Timer?
    private var hoverCancellable: AnyCancellable?
    private var glowCancellable: AnyCancellable?
    private var pointer: PointerWatcher?
    private var peekUntil: Date?
    private var timer: Timer?
    private var batteryTimer: Timer?

    init(calendar: CalendarService, music: MusicService, battery: BatteryService, clipboard: ClipboardService, timer: TimerService) {
        self.calendar = calendar
        self.music = music
        self.battery = battery
        self.clipboard = clipboard
        self.timerService = timer
        timer.onChange = { [weak self] in
            guard let self else { return }
            evaluate()
            // Hover was ignored while "Time's up" showed; if the pointer is still on the notch, open the panel.
            if !timerService.doneShowing, notch?.isHovering == true { hoverChanged(true) }
        }
        battery.onAlert = { [weak self] alert in self?.flashBattery(alert) }
        calendar.onUpdate = { [weak self] in self?.evaluate() }
        music.onChange = { [weak self] in self?.evaluate() }
        music.onPlay = { [weak self] in
            // No compact state on screens without a notch, so peek briefly instead.
            guard let self, !Self.targetScreen().hasNotchInset else { return }
            peekUntil = Date().addingTimeInterval(Self.peekDuration)
            evaluate()
        }
    }

    func start() {
        let notch = NotchPresenter(
            expanded: { [unowned self] in
                NotchRootView(
                    state: state,
                    music: music,
                    calendar: calendar,
                    clipboard: clipboard,
                    timer: timerService,
                    onJoin: { [weak self] url in
                        NSWorkspace.shared.open(url)
                        self?.dismissCurrent()
                    },
                    onDismiss: { [weak self] in self?.dismissCurrent() }
                )
            },
            leading: { [unowned self] in CompactLeading(state: state, music: music, timer: timerService) },
            trailing: { [unowned self] in CompactTrailing(state: state, music: music, timer: timerService) }
        )
        self.notch = notch

        // Keeps the glow around the shape in step with the open tab and the album, which the notch's view doesn't watch.
        glowCancellable = Publishers.CombineLatest3(state.$content, state.$tab, music.objectWillChange.prepend(()))
            .receive(on: RunLoop.main)
            .sink { [weak self] content, tab, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let colour = NotchDecision.glowColor(content: content, tab: tab, accent: self.music.accent)
                    if self.notch?.glowColor != colour { self.notch?.glowColor = colour }
                }
            }

        // Hover state comes from the notch's view; the dwell/leave timing and expansion are ours.
        hoverCancellable = notch.$isHovering
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hovering in
                MainActor.assumeIsolated { self?.hoverChanged(hovering) }
            }

        // Hover and click-through follow the pointer position.
        pointer = PointerWatcher { [weak self] point in self?.notch?.pointerMoved(to: point) }
        pointer?.start()

        // Local tick only: starts/ends the meeting popup at the right second.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerService.checkFinished()   // catches a countdown that ended while the Mac slept
                self?.evaluate()
            }
        }
    }

    /// Shows the battery flash for a few seconds over whatever the notch shows, then puts that back.
    private func flashBattery(_ alert: BatteryAlert) {
        // Compact areas only exist beside a real notch; elsewhere there's nowhere to flash.
        guard Self.targetScreen().hasNotchInset else { return }
        state.battery = alert
        if applied == .battery {
            startFlashClock()   // already compact: a new alert restarts the flash
        } else {
            state.batteryShownAt = nil   // the clock starts once the compact notch is showing
            evaluate()
        }
    }

    /// Starts the sweep and the 3 s countdown. Called once the compact areas are on screen,
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
        // Hover was ignored during the flash; if the pointer is still on the notch, open it now.
        if notch?.isHovering == true { hoverChanged(true) }
    }

    private func dismissCurrent() {
        if let key = currentReminder { dismissed.insert(key) }
        evaluate()
    }

    // MARK: Hover

    private func hoverChanged(_ hovering: Bool) {
        Self.log.info("hover \(hovering, privacy: .public)")
        hoverTimer?.invalidate()
        hoverTimer = nil
        if hovering {
            guard desired == .musicCompact || desired == .idle else { return }
            hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverDwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.notch?.isHovering == true else { return }
                    self.state.tab = HoverTab.opening(last: self.state.lastTab, hasTrack: self.music.track != nil)
                    self.hoverExpanded = true
                    self.evaluate()
                }
            }
        } else if hoverExpanded {
            hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverLeaveDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.notch?.isHovering != true else { return }
                    self.hoverExpanded = false
                    self.evaluate()
                }
            }
        }
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
        let inputs = NotchInputs(
            hasReminder: target != nil,
            musicShowsCard: music.showsCard,
            screenHasNotch: Self.targetScreen().hasNotchInset,
            hoverExpanded: hoverExpanded,
            peeking: (peekUntil ?? .distantPast) > now,
            timerDoneShowing: timerService.doneShowing,
            batteryFlashing: state.battery != nil
        )
        hoverExpanded = NotchDecision.keepsHoverExpanded(inputs)
        desired = NotchDecision.mode(for: inputs)
        reconcile()
    }

    /// Applies `desired` one transition at a time; re-checks afterwards in case it changed mid-animation.
    private func reconcile() {
        guard !reconciling, applied != desired else { return }
        reconciling = true
        Task {
            while applied != desired {
                let mode = desired
                applied = mode
                Self.log.info("mode -> \(String(describing: mode), privacy: .public)")
                await perform(mode)
            }
            reconciling = false
        }
    }

    /// The notch's window can take the keyboard; by default a click there keeps it, so ⌘V straight after
    /// clicking a clipboard row would land in Mantel. This keeps it only when something needs typing.
    /// `NotchPanel` sets it too; this is a guard in case the window is ever rebuilt differently.
    private func keepKeyboardInFrontApp() {
        notch?.window?.becomesKeyOnlyIfNeeded = true
    }

    private func perform(_ mode: NotchMode) async {
        // The music tab's progress bar needs the position; the panel opens from both music and idle.
        music.setPolling(mode == .musicExpanded || mode == .idleExpanded)
        let screen = Self.targetScreen()
        switch mode {
        case .hidden: await notch?.hide()
        case .musicCompact, .idle: await notch?.compact(on: screen)
        case .battery:
            await notch?.compact(on: screen)
            if desired == .battery { startFlashClock() }
        case .musicExpanded:
            // Hovering a notch opens the panel; without a notch this is the brief peek at a new song.
            state.content = screen.hasNotchInset ? .panel : .music
            await notch?.expand(on: screen)
        case .idleExpanded:
            state.content = .panel
            await notch?.expand(on: screen)
        case .meeting:
            state.content = .meeting
            await notch?.expand(on: screen)
        case .timerDone:
            state.content = .timerDone
            await notch?.expand(on: screen)
            timerService.doneAppeared()   // its 10 seconds start now it's actually on screen
        }
        keepKeyboardInFrontApp()
    }

    /// Prefer the built-in display (the one with a notch); otherwise the main screen.
    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.notchMetrics.hasNotch } ?? NSScreen.screens[0]
    }
}

private extension NSScreen {
    var hasNotchInset: Bool { notchMetrics.hasNotch }
}
