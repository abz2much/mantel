import AppKit
import SwiftUI
import Testing
@testable import Notch

@MainActor
private final class FakePresenter: NotchPresenting {
    var isHovering = false
    var window: NSPanel? { nil }
    var glowColor: Color = .orange
    var calls: [String] = []
    func expand(on screen: NSScreen) async { calls.append("expand"); try? await Task.sleep(for: .milliseconds(50)) }
    func compact(on screen: NSScreen) async { calls.append("compact"); try? await Task.sleep(for: .milliseconds(50)) }
    func hide() async { calls.append("hide") }
    func pointerMoved(to point: CGPoint) {}
}

private let zone = CGRect(x: 2240, y: 877, width: 464, height: 3)
private let insideZone = CGPoint(x: zone.midX, y: zone.midY)

@MainActor
@Test func stageAppliesLatestMode() async throws {
    let fake = FakePresenter()
    let stage = NotchStage(screenID: 2, presenter: fake, onHoverExpandedChange: { _ in })
    let perform: (NotchMode) async -> Void = { mode in
        switch mode {
        case .idleExpanded: await fake.expand(on: NSScreen())
        default: await fake.compact(on: NSScreen())
        }
    }
    stage.apply(.idle, perform: perform)
    stage.apply(.idleExpanded, perform: perform)
    try await Task.sleep(for: .milliseconds(250))
    #expect(fake.calls.last == "expand")
    #expect(stage.applied == .idleExpanded)
}

@MainActor
@Test func hoverZoneStartsHoverAfterDwell() async throws {
    var changes: [Bool] = []
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { changes.append($0) })
    stage.desired = .hidden
    stage.pointerMoved(to: insideZone, zone: zone)
    #expect(!stage.hoverExpanded)
    try await Task.sleep(for: .milliseconds(350))
    #expect(stage.hoverExpanded)
    #expect(changes == [true])
}

@MainActor
@Test func leavingClosesAfterDelay() async throws {
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { _ in })
    stage.desired = .hidden
    stage.pointerMoved(to: insideZone, zone: zone)
    try await Task.sleep(for: .milliseconds(350))
    stage.pointerMoved(to: CGPoint(x: 0, y: 0), zone: zone)
    try await Task.sleep(for: .milliseconds(300))
    #expect(stage.hoverExpanded)
    try await Task.sleep(for: .milliseconds(300))
    #expect(!stage.hoverExpanded)
}

@Test func screensRebuiltOnDisplayChange() {
    let screens = [ScreenInfo(id: 1, hasNotch: true, isMain: true), ScreenInfo(id: 2, hasNotch: false, isMain: false)]
    let diff = NotchController.stageIDs(for: screens, current: [1, 3])
    #expect(diff.add == [2])
    #expect(diff.remove == [3])
}
