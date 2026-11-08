import AppKit
import SwiftUI

/// What a stage needs from its notch window. `NotchPresenter` is the real one; tests use a fake.
@MainActor
protocol NotchPresenting: AnyObject {
    var isHovering: Bool { get }
    var window: NSPanel? { get }
    var glowColor: Color { get set }
    func expand(on screen: NSScreen) async
    func compact(on screen: NSScreen) async
    func hide() async
    func pointerMoved(to point: CGPoint)
    /// Closes at once, without waiting for the pointer: the screen is gone.
    func tearDown()
}

extension NotchPresenter: NotchPresenting {}

/// Per-screen bits the shared views need: only the alert screen shows the battery sweep.
@MainActor
final class StageFlags: ObservableObject {
    @Published var showsBattery = false
}

/// One screen's notch: its window, its reconcile loop and its hover timing.
@MainActor
final class NotchStage {
    static let hoverDwell: TimeInterval = 0.3
    static let hoverLeaveDelay: TimeInterval = 0.5

    let screenID: Int
    let presenter: NotchPresenting
    let flags: StageFlags
    var desired: NotchMode = .hidden
    private(set) var applied: NotchMode = .hidden
    var hoverExpanded = false
    private(set) var pointerInside = false
    /// Opened from the keyboard: stays open until closed on purpose, wherever the pointer goes.
    private(set) var pinned = false

    private var reconciling = false
    private var hoverTimer: Timer?
    private let onHoverExpandedChange: (Bool) -> Void

    init(screenID: Int, presenter: NotchPresenting, flags: StageFlags? = nil,
         onHoverExpandedChange: @escaping (Bool) -> Void) {
        self.screenID = screenID
        self.presenter = presenter
        self.flags = flags ?? StageFlags()
        self.onHoverExpandedChange = onHoverExpandedChange
    }

    /// Moves to `mode` one transition at a time; re-checks afterwards in case it changed mid-animation.
    func apply(_ mode: NotchMode, perform: @escaping (NotchMode) async -> Void) {
        desired = mode
        guard !reconciling, applied != desired else { return }
        reconciling = true
        Task {
            while applied != desired {
                let next = desired
                applied = next
                await perform(next)
            }
            reconciling = false
        }
    }

    /// Hover starts from the notch's shape, or on a monitor from the strip at the top (`zone`).
    func pointerMoved(to point: CGPoint, zone: CGRect?) {
        presenter.pointerMoved(to: point)
        let inside = presenter.isHovering || (zone?.contains(point) ?? false)
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverTimer?.invalidate()
        hoverTimer = nil
        if inside {
            startDwell()
        } else if hoverExpanded, !pinned {
            hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverLeaveDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.pointerInside, self.hoverExpanded, !self.pinned else { return }
                    self.hoverExpanded = false
                    self.onHoverExpandedChange(false)
                }
            }
        }
    }

    /// Opens the panel from the keyboard, ignoring the pointer until `unpin()`.
    func pin() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        pinned = true
        hoverExpanded = true
    }

    func unpin() {
        pinned = false
        hoverExpanded = false
    }

    /// The screen went away: stop timers and close the window now.
    func tearDown() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        pointerInside = false
        presenter.tearDown()
    }

    /// After an alert ends with the pointer still there, open the panel as if it had just arrived.
    func recheckHover() {
        guard pointerInside, !hoverExpanded, hoverTimer == nil else { return }
        startDwell()
    }

    private var canStartHover: Bool { [.idle, .musicCompact, .tab, .hidden].contains(desired) }

    private func startDwell() {
        guard canStartHover else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverTimer = nil
                guard self.pointerInside, !self.hoverExpanded, self.canStartHover else { return }
                self.hoverExpanded = true
                self.onHoverExpandedChange(true)
            }
        }
    }
}
