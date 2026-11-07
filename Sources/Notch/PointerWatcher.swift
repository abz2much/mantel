import AppKit

/// Polls the pointer position. Needs no permission, unlike watching mouse events from other apps.
@MainActor
final class PointerWatcher {
    private let interval: TimeInterval
    private let onMove: (CGPoint) -> Void
    private var timer: Timer?
    private var last: CGPoint?

    init(interval: TimeInterval = 0.05, onMove: @escaping (CGPoint) -> Void) {
        self.interval = interval
        self.onMove = onMove
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps running while a menu is open
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        guard point != last else { return }
        last = point
        onMove(point)
    }
}
