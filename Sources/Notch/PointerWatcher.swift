import AppKit

/// Polls the pointer position. Needs no permission, unlike watching mouse events from other apps.
/// Reports every tick, even when the pointer is still, because the shapes under it change size.
@MainActor
final class PointerWatcher {
    private let interval: TimeInterval
    private let onMove: (CGPoint) -> Void
    private var timer: Timer?
    private let position: () -> CGPoint

    init(interval: TimeInterval = 0.05, position: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         onMove: @escaping (CGPoint) -> Void) {
        self.interval = interval
        self.position = position
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

    func tick() {
        onMove(position())
    }
}
