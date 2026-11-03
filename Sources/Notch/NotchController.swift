import AppKit
import Combine
import DynamicNotchKit
import SwiftUI
import os

@MainActor
final class NotchState: ObservableObject {
    @Published var event: MeetingEvent?
    @Published var showMeeting = false
}

/// Decides what the notch shows (meeting > music > nothing) and drives it.
@MainActor
final class NotchController {
    private static let hoverDwell: TimeInterval = 0.3
    private static let hoverLeaveDelay: TimeInterval = 0.5
    private static let peekDuration: TimeInterval = 6

    private static let log = Logger(subsystem: "local.notch.app", category: "notch")

    private enum Mode: Equatable { case hidden, musicCompact, musicExpanded, meeting }

    private let calendar: CalendarService
    private let spotify: SpotifyService
    private let state = NotchState()
    private var notch: DynamicNotch<NotchRootView, MusicCompactLeading, MusicCompactTrailing>?

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

    init(calendar: CalendarService, spotify: SpotifyService) {
        self.calendar = calendar
        self.spotify = spotify
        calendar.onUpdate = { [weak self] in self?.evaluate() }
        spotify.onChange = { [weak self] in self?.evaluate() }
        spotify.onPlay = { [weak self] in
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
                    spotify: spotify,
                    onJoin: { [weak self] url in
                        NSWorkspace.shared.open(url)
                        self?.dismissCurrent()
                    },
                    onDismiss: { [weak self] in self?.dismissCurrent() }
                )
            },
            compactLeading: { [unowned self] in MusicCompactLeading(spotify: spotify) },
            compactTrailing: { [unowned self] in MusicCompactTrailing(spotify: spotify) }
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
            guard desired == .musicCompact else { return }
            hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverDwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.notch?.isHovering == true else { return }
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
            state.showMeeting = true
            currentReminder = target.key
            hoverExpanded = false
            desired = .meeting
        } else {
            currentReminder = nil
            if spotify.showsCard {
                if Self.targetScreen().hasNotchInset {
                    desired = hoverExpanded ? .musicExpanded : .musicCompact
                } else {
                    desired = (peekUntil ?? .distantPast) > now ? .musicExpanded : .hidden
                }
            } else {
                hoverExpanded = false
                desired = .hidden
            }
        }
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
        spotify.setPolling(mode == .musicExpanded)
        let screen = Self.targetScreen()
        switch mode {
        case .hidden: await notch?.hide()
        case .musicCompact: await notch?.compact(on: screen)
        case .musicExpanded:
            state.showMeeting = false
            await notch?.expand(on: screen)
        case .meeting: await notch?.expand(on: screen)
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
