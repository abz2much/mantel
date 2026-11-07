import AppKit
import SwiftUI

/// Borderless, non-activating, above everything, on every Space. Takes the keyboard only if something needs typing.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
}

/// Only the black shape answers clicks; the rest of the (large, transparent) window ignores them.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var hitRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        var local = convert(point, from: superview)
        if !isFlipped { local.y = bounds.height - local.y }
        return hitRect().contains(local) ? super.hitTest(point) : nil
    }
}

/// Mantel's own notch: one window at the top centre of a screen, with a black shape that is hidden,
/// compact (the side pieces beside the notch) or expanded (the panel).
@MainActor
final class NotchPresenter<Expanded: View, Leading: View, Trailing: View>: ObservableObject {
    @Published private(set) var isHovering = false
    @Published private(set) var presentation: NotchPresentation = .hidden
    @Published private(set) var metrics = NotchMetrics(notchSize: .zero, menubarHeight: 0, hasNotch: false)
    /// Strength of the coloured glow around the shape: 0.9 at the flash's peak, 0.35 while open.
    @Published private(set) var glowStrength: CGFloat = 0
    /// Colour of that glow; the controller keeps it in step with the open tab and the album.
    @Published var glowColor: Color = MantelStyle.glow

    // Measured by the view; used for the click area and centring.
    var expandedSize: CGSize = .zero
    @Published var sideWidths: (leading: CGFloat, trailing: CGFloat) = (0, 0)

    let expanded: () -> Expanded
    let leading: () -> Leading
    let trailing: () -> Trailing

    private(set) var window: NSPanel?
    private var screenNumber: NSNumber?
    private var generation = 0
    private var screenObserver: NSObjectProtocol?

    init(expanded: @escaping () -> Expanded, leading: @escaping () -> Leading,
         trailing: @escaping () -> Trailing) {
        self.expanded = expanded
        self.leading = leading
        self.trailing = trailing
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: The surface the controller uses

    func expand(on screen: NSScreen) async {
        request(.expanded, on: screen)
        try? await Task.sleep(for: .seconds(NotchMotion.openDuration))
    }

    func compact(on screen: NSScreen) async {
        request(.compact, on: screen)
        try? await Task.sleep(for: .seconds(NotchMotion.openDuration))
    }

    /// Waits while the pointer is still on the shape, then closes.
    func hide() async {
        guard window != nil else { presentation = .hidden; return }
        while isHovering, window != nil {
            try? await Task.sleep(for: .seconds(0.1))
        }
        request(.hidden, on: nil)
        try? await Task.sleep(for: .seconds(NotchMotion.closeDuration + 0.02))
    }

    /// Moves straight to `target`. Later requests win: a close that finishes after a re-open does nothing.
    func request(_ target: NotchPresentation, on screen: NSScreen?) {
        generation += 1
        let gen = generation

        guard target != .hidden else {
            guard window != nil else { presentation = .hidden; return }
            withAnimation(NotchMotion.close) {
                presentation = .hidden
                glowStrength = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.closeDuration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    self.closeWindow()
                }
            }
            return
        }

        guard let screen else { return }
        let fresh = window == nil || screen.screenNumber != screenNumber
        if fresh {
            closeWindow()
            makeWindow(on: screen)
        }
        let settledGlow: CGFloat = target == .expanded ? 0.35 : 0
        let open = { [weak self] in
            guard let self, self.generation == gen else { return }
            let flash = NotchMotion.flashes(from: self.presentation, to: target)
            withAnimation(NotchMotion.open) {
                self.presentation = target
                if !flash { self.glowStrength = settledGlow }
            }
            guard flash else { return }
            withAnimation(.easeOut(duration: NotchMotion.flashLead)) { self.glowStrength = 0.9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.flashLead) {
                MainActor.assumeIsolated {
                    guard self.generation == gen else { return }
                    withAnimation(.easeOut(duration: NotchMotion.openDuration - NotchMotion.flashLead)) {
                        self.glowStrength = settledGlow
                    }
                }
            }
        }
        if fresh {
            // Let the window draw once at the closed size, so the opening animates from the notch.
            DispatchQueue.main.async { MainActor.assumeIsolated { open() } }
        } else {
            open()
        }
    }

    /// The pointer moved (screen coordinates). Over the black shape it hovers and the window takes clicks;
    /// anywhere else, including the glow around the shape, clicks go straight to whatever is underneath.
    func pointerMoved(to point: CGPoint) {
        guard let window else { return }
        let over = presentation != .hidden && shapeFrameOnScreen.contains(point)
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        if over != isHovering { isHovering = over }
    }

    /// The black shape's frame in screen coordinates; zero when nothing is showing.
    var shapeFrameOnScreen: CGRect {
        guard let window, presentation != .hidden else { return .zero }
        let rect = Self.shapeRect(presentation: presentation, metrics: metrics, contentSize: expandedSize,
                                  sides: sideWidths, windowSize: window.frame.size)
        return NotchGeometry.screenRect(windowRect: rect, windowFrame: window.frame)
    }

    // MARK: Click area

    /// The black shape's frame inside the window, top-left origin.
    nonisolated static func shapeRect(presentation: NotchPresentation, metrics: NotchMetrics, contentSize: CGSize,
                                      sides: (leading: CGFloat, trailing: CGFloat), windowSize: CGSize) -> CGRect {
        let top = NotchMotion.radii(for: presentation).top
        let size: CGSize
        var offset: CGFloat = 0
        switch presentation {
        case .hidden:
            return .zero
        case .expanded:
            size = CGSize(width: max(contentSize.width, metrics.notchSize.width) + top * 2, height: contentSize.height)
        case .compact:
            size = CGSize(width: metrics.notchSize.width + sides.leading + sides.trailing + top * 2,
                          height: max(metrics.notchSize.height, metrics.menubarHeight))
            offset = NotchGeometry.compactOffset(leading: sides.leading, trailing: sides.trailing)
        }
        return CGRect(x: (windowSize.width - size.width) / 2 + offset, y: 0, width: size.width, height: size.height)
    }

    // MARK: Window

    private func makeWindow(on screen: NSScreen) {
        metrics = screen.notchMetrics
        screenNumber = screen.screenNumber
        presentation = .hidden
        glowStrength = 0
        let frame = NotchGeometry.windowFrame(screenFrame: screen.frame)
        let panel = NotchPanel(frame: frame)
        panel.ignoresMouseEvents = true   // until the pointer is over the shape
        let host = NotchHostingView(rootView: NotchSurface(presenter: self))
        host.hitRect = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return .zero }
                return Self.shapeRect(presentation: self.presentation, metrics: self.metrics,
                                      contentSize: self.expandedSize, sides: self.sideWidths,
                                      windowSize: self.window?.frame.size ?? frame.size)
            }
        }
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        window = panel
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        screenNumber = nil
        isHovering = false
        presentation = .hidden
    }

    /// Displays changed: put the window back at the top of its screen, or the first screen if that one's gone.
    private func screensChanged() {
        guard let window else { return }
        let screen = NSScreen.screens.first { $0.screenNumber == screenNumber } ?? NSScreen.screens.first
        guard let screen else { return }
        metrics = screen.notchMetrics
        screenNumber = screen.screenNumber
        window.setFrame(NotchGeometry.windowFrame(screenFrame: screen.frame), display: true)
    }
}

extension NSScreen {
    var screenNumber: NSNumber? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
}
