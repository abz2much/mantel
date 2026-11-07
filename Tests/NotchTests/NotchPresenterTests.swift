import AppKit
import Combine
import SwiftUI
import Testing
@testable import Notch

private let laptopNotch = NotchMetrics(notchSize: CGSize(width: 212, height: 32), menubarHeight: 32, hasNotch: true)
private let window = CGSize(width: 756, height: 491)

@Test func hitAreaIsOnlyTheShape() {
    let expanded = NotchPresenter<EmptyView, EmptyView, EmptyView>.shapeRect(
        presentation: .expanded, metrics: laptopNotch, contentSize: CGSize(width: 404, height: 220),
        sides: (leading: 0, trailing: 0), windowSize: window)
    #expect(expanded == CGRect(x: 161, y: 0, width: 434, height: 220))
    #expect(!expanded.contains(CGPoint(x: expanded.minX - 5, y: 100)))
    #expect(!expanded.contains(CGPoint(x: 300, y: expanded.maxY + 5)))

    let compact = NotchPresenter<EmptyView, EmptyView, EmptyView>.shapeRect(
        presentation: .compact, metrics: laptopNotch, contentSize: .zero,
        sides: (leading: 40, trailing: 60), windowSize: window)
    #expect(compact == CGRect(x: 226, y: 0, width: 324, height: 32))

    let hidden = NotchPresenter<EmptyView, EmptyView, EmptyView>.shapeRect(
        presentation: .hidden, metrics: laptopNotch, contentSize: .zero,
        sides: (leading: 0, trailing: 0), windowSize: window)
    #expect(hidden == .zero)
}

@MainActor
private func makePresenter() -> NotchPresenter<Text, EmptyView, EmptyView> {
    NotchPresenter(expanded: { Text("panel") }, leading: { EmptyView() }, trailing: { EmptyView() })
}

@MainActor
@Test(.enabled(if: !NSScreen.screens.isEmpty))
func presenterEndsInLatestState() async throws {
    let screen = NSScreen.screens[0]
    let p = makePresenter()

    // Rapid requests settle on the last one.
    p.request(.expanded, on: screen)
    p.request(.compact, on: screen)
    p.request(.hidden, on: screen)
    let deadline = ContinuousClock.now + .seconds(2)
    while p.window != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(p.presentation == .hidden)
    #expect(p.window == nil)

    // Re-opening during a close isn't undone by the earlier close finishing.
    await p.expand(on: screen)
    p.request(.hidden, on: screen)
    p.request(.expanded, on: screen)
    try await Task.sleep(for: .seconds(NotchMotion.closeDuration + 0.2))
    #expect(p.presentation == .expanded)
    #expect(p.window != nil)

    await p.hide()
    #expect(p.window == nil)
}

@MainActor
@Test func glowColourChangeRedrawsSurface() {
    let p = makePresenter()
    var changes = 0
    let sub = p.objectWillChange.sink { changes += 1 }
    p.glowColor = .red
    #expect(changes == 1)
    #expect(p.glowColor == .red)
    sub.cancel()
}

@Test func glowTakesAlbumColourOnlyOnMusicPanel() {
    #expect(NotchDecision.glowColor(content: .panel, tab: .music, accent: .red) == .red)
    #expect(NotchDecision.glowColor(content: .panel, tab: .clipboard, accent: .red) == MantelStyle.glow)
    #expect(NotchDecision.glowColor(content: .meeting, tab: .music, accent: .red) == MantelStyle.glow)
    #expect(NotchDecision.glowColor(content: .panel, tab: .music, accent: nil) == MantelStyle.glow)
}

@MainActor
@Test(.enabled(if: !NSScreen.screens.isEmpty))
func pointerOverShapeHoversAndTakesClicks() async {
    let p = makePresenter()
    await p.expand(on: NSScreen.screens[0])
    try? await Task.sleep(for: .seconds(0.1))
    let shape = p.shapeFrameOnScreen
    #expect(shape != .zero)
    p.pointerMoved(to: CGPoint(x: shape.midX, y: shape.midY))
    #expect(p.isHovering)
    #expect(p.window?.ignoresMouseEvents == false)
    p.pointerMoved(to: CGPoint(x: shape.minX - 10, y: shape.midY))
    #expect(!p.isHovering)
    #expect(p.window?.ignoresMouseEvents == true)
    await p.hide()
}

@MainActor
@Test func hideReturnsAtOnceWhenNothingShows() async {
    let p = makePresenter()
    let elapsed = await ContinuousClock().measure { await p.hide() }
    #expect(elapsed < .milliseconds(50))
}

@Test func monitorTabIsCentred() {
    let monitor = NotchMetrics(notchSize: CGSize(width: 0, height: 24), menubarHeight: 24, hasNotch: false)
    let tab = NotchPresenter<EmptyView, EmptyView, EmptyView>.shapeRect(
        presentation: .compact, metrics: monitor, contentSize: .zero,
        sides: (leading: 180, trailing: 0), windowSize: CGSize(width: 1720, height: 720))
    #expect(tab.midX == 860)
}

@MainActor
@Test(.enabled(if: !NSScreen.screens.isEmpty))
func tearDownClosesAtOnceEvenWhileHovered() async {
    let p = makePresenter()
    await p.expand(on: NSScreen.screens[0])
    try? await Task.sleep(for: .seconds(0.1))
    let shape = p.shapeFrameOnScreen
    p.pointerMoved(to: CGPoint(x: shape.midX, y: shape.midY))
    #expect(p.isHovering)
    p.tearDown()
    #expect(p.window == nil)
    #expect(!p.isHovering)
}

@MainActor
@Test func watcherReportsAStillPointerToo() {
    var moves = 0
    let w = PointerWatcher(position: { CGPoint(x: 10, y: 10) }, onMove: { _ in moves += 1 })
    w.tick()
    w.tick()
    #expect(moves == 2)
}
