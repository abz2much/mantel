import AppKit

/// A screen's notch, in points. Screens without a notch report a zero-width "notch" as tall as the menu bar.
struct NotchMetrics: Equatable {
    let notchSize: CGSize
    let menubarHeight: CGFloat
    let hasNotch: Bool
}

/// Notch sizes and window placement, as plain sums so they can be tested without a real screen.
enum NotchGeometry {
    static func metrics(screenFrame: CGRect, visibleFrame: CGRect,
                        leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?, topInset: CGFloat) -> NotchMetrics {
        let menubar = screenFrame.maxY - visibleFrame.maxY
        guard let left = leftAuxWidth, let right = rightAuxWidth else {
            return NotchMetrics(notchSize: CGSize(width: 0, height: menubar), menubarHeight: menubar, hasNotch: false)
        }
        return NotchMetrics(notchSize: CGSize(width: screenFrame.width - left - right, height: topInset),
                            menubarHeight: menubar, hasNotch: true)
    }

    /// The window covers the top-centre half of the screen; only the black shape inside it takes clicks.
    static func windowFrame(screenFrame: CGRect) -> CGRect {
        let size = CGSize(width: screenFrame.width / 2, height: screenFrame.height / 2)
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Converts a rect inside the window (top-left origin) into screen coordinates (bottom-left origin).
    static func screenRect(windowRect: CGRect, windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + windowRect.minX, y: windowFrame.maxY - windowRect.maxY,
               width: windowRect.width, height: windowRect.height)
    }

    /// On a monitor, the strip at the very top centre that opens the panel: the panel's width plus a margin, 3 pt tall.
    static func hoverZone(screenFrame: CGRect) -> CGRect {
        let width: CGFloat = 464, height: CGFloat = 3
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Shifts the compact shape so the notch stays centred over the camera when the two sides differ in width.
    static func compactOffset(leading: CGFloat, trailing: CGFloat) -> CGFloat {
        (trailing - leading) / 2
    }
}

extension NSScreen {
    var notchMetrics: NotchMetrics {
        NotchGeometry.metrics(screenFrame: frame, visibleFrame: visibleFrame,
                              leftAuxWidth: auxiliaryTopLeftArea?.width, rightAuxWidth: auxiliaryTopRightArea?.width,
                              topInset: safeAreaInsets.top)
    }
}
