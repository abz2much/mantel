import AppKit
import Combine
import DynamicNotchKit
import SwiftUI
import os

@MainActor
final class NotchState: ObservableObject {
    /// What the expanded notch shows: a meeting reminder, the music card on its own (a peek on
    /// screens without a notch), or the hover panel with its tabs.
    enum Content { case meeting, music, panel }

    @Published var event: MeetingEvent?
    @Published var content: Content = .music
    /// The hover panel's open tab, and the one last picked (reopened next time).
    @Published var tab: HoverTab = .music
    var lastTab: HoverTab?
    /// The battery flash showing in the compact notch, if any, and when it started.
    @Published var battery: BatteryAlert?
    @Published var batteryShownAt: Date?
}

/// Decides what the notch shows (battery flash > meeting > music > idle) and drives it.
@MainActor
final class NotchController {
    private static let hoverDwell: TimeInterval = 0.3
    private static let hoverLeaveDelay: TimeInterval = 0.5
    private static let peekDuration: TimeInterval = 6
    private static let batteryFlashDuration: TimeInterval = 3

    private static let log = Logger(subsystem: "local.notch.app", category: "notch")

    private enum Mode: Equatable { case hidden, musicCompact, musicExpanded, idle, idleExpanded, meeting, battery }

    private let calendar: CalendarService
    private let music: MusicService
    private let battery: BatteryService
    private let clipboard: ClipboardService
    private let state = NotchState()
    private var notch: DynamicNotch<NotchRootView, CompactLeading, CompactTrailing>?

    private var dismissed: Set<ReminderKey> = []
    private var currentReminder: ReminderKey?

    private var desired: Mode = .hidden
    private var applied: Mode = .hidden
    private var reconciling = false

    private var hoverExpanded = false
    private var hoverTimer: Timer?
    private var hoverCancellable: AnyCancellable?
    private var peekUntil: Date?
    private var timer: Timer?
    private var batteryTimer: Timer?

    init(calendar: CalendarService, music: MusicService, battery: BatteryService, clipboard: ClipboardService) {
        self.calendar = calendar
        self.music = music
        self.battery = battery
        self.clipboard = clipboard
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
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto,
            expanded: { [unowned self] in
                NotchRootView(
                    state: state,
                    music: music,
                    calendar: calendar,
                    clipboard: clipboard,
                    onJoin: { [weak self] url in
                        NSWorkspace.shared.open(url)
                        self?.dismissCurrent()
                    },
                    onDismiss: { [weak self] in self?.dismissCurrent() }
                )
            },
            compactLeading: { [unowned self] in CompactLeading(state: state, music: music) },
            compactTrailing: { [unowned self] in CompactTrailing(state: state, music: music) }
        )
        self.notch = notch

        // Hover state comes from DynamicNotchKit's view; the dwell/leave timing and expansion are ours.
        hoverCancellable = notch.$isHovering
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hovering in
                MainActor.assumeIsolated { self?.hoverChanged(hovering) }
            }

        // Local tick only: starts/ends the meeting popup at the right second.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
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
            hoverExpanded = false
            desired = .meeting
        } else {
            currentReminder = nil
            if music.showsCard {
                if Self.targetScreen().hasNotchInset {
                    desired = hoverExpanded ? .musicExpanded : .musicCompact
                } else {
                    desired = (peekUntil ?? .distantPast) > now ? .musicExpanded : .hidden
                }
            } else if Self.targetScreen().hasNotchInset {
                // Idle: keep an empty compact notch so hovering it can open today's agenda.
                desired = hoverExpanded ? .idleExpanded : .idle
            } else {
                hoverExpanded = false
                desired = .hidden
            }
        }
        if state.battery != nil { desired = .battery }
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

    private func perform(_ mode: Mode) async {
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
        }
    }

    /// Prefer the built-in display (the one with a notch); otherwise the main screen.
    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens[0]
    }
}

private extension NSScreen {
    var hasNotchInset: Bool { safeAreaInsets.top > 0 }
}
