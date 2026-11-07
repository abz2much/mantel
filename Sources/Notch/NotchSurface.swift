import SwiftUI

/// The black notch shape and what's inside it, drawn at the top centre of the notch window.
struct NotchSurface<Expanded: View, Leading: View, Trailing: View>: View {
    @ObservedObject var presenter: NotchPresenter<Expanded, Leading, Trailing>

    /// Space around the panel inside the black shape (the notch height is added on top).
    private static var inset: CGFloat { 15 }

    private var metrics: NotchMetrics { presenter.metrics }
    private var radii: (top: CGFloat, bottom: CGFloat) { NotchMotion.radii(for: presenter.presentation) }

    /// The closed shape sits exactly over the camera; without a notch it has no height at all.
    private var minHeight: CGFloat {
        switch presenter.presentation {
        case .hidden: metrics.hasNotch ? metrics.notchSize.height : 0
        case .compact: presenter.isHovering ? max(metrics.notchSize.height, metrics.menubarHeight) : metrics.notchSize.height
        case .expanded: metrics.notchSize.height
        }
    }

    private var shadow: (opacity: Double, radius: CGFloat) {
        switch (presenter.presentation, presenter.isHovering) {
        case (.hidden, _): (0, 0)
        case (_, true): (0.8, 20)
        case (.compact, false): (0, 10)
        case (.expanded, false): (0.5, 10)
        }
    }

    var body: some View {
        shape
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: some View {
        ZStack(alignment: .top) {
            if presenter.presentation == .compact {
                compactRow
                    .transition(.opacity.animation(.easeOut(duration: NotchMotion.openDuration)))
            }
            if presenter.presentation == .expanded {
                expandedBody
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6))
                            .animation(.easeOut(duration: NotchMotion.openDuration * 0.84)
                                .delay(NotchMotion.openDuration * 0.56)),
                        removal: .opacity.animation(.linear(duration: NotchMotion.closeDuration * 0.5))
                    ))
            }
        }
        .padding(.horizontal, radii.top)
        .frame(minWidth: metrics.notchSize.width + radii.top * 2, minHeight: minHeight, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .shadow(color: presenter.glowColor.opacity(presenter.glowStrength), radius: 30 - 13 * presenter.glowStrength)
        .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius)
        .contentShape(Rectangle())
        .onHover { presenter.setHovering($0) }
        .offset(x: presenter.presentation == .compact
                ? NotchGeometry.compactOffset(leading: presenter.sideWidths.leading, trailing: presenter.sideWidths.trailing)
                : 0)
        .foregroundStyle(.white)
    }

    private var compactRow: some View {
        HStack(spacing: 0) {
            presenter.leading()
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 8) }
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { presenter.sideWidths.leading = $0 }
            Spacer().frame(width: metrics.notchSize.width)
            presenter.trailing()
                .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 8) }
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { presenter.sideWidths.trailing = $0 }
        }
        .frame(height: minHeight)
    }

    private var expandedBody: some View {
        presenter.expanded()
            .fixedSize()
            .padding(.top, metrics.notchSize.height)
            .padding([.leading, .trailing, .bottom], Self.inset)
            .frame(minWidth: metrics.notchSize.width)
            .onGeometryChange(for: CGSize.self, of: \.size) { presenter.expandedSize = $0 }
    }
}
