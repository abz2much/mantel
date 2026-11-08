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
    func tearDown() { calls.append("tearDown") }
}

/// Waits until `condition` holds (or 2 s pass), so timing tests don't depend on a fast machine.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
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
    #expect(await eventually { fake.calls.last == "expand" })
    #expect(stage.applied == .idleExpanded)
}

@MainActor
@Test func hoverZoneStartsHoverAfterDwell() async throws {
    var changes: [Bool] = []
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { changes.append($0) })
    stage.desired = .hidden
    stage.pointerMoved(to: insideZone, zone: zone)
    #expect(!stage.hoverExpanded)
    try await Task.sleep(for: .milliseconds(150))
    #expect(!stage.hoverExpanded)   // still waiting out the 0.3 s dwell
    #expect(await eventually { stage.hoverExpanded })
    #expect(changes == [true])
}

@MainActor
@Test func leavingClosesAfterDelay() async throws {
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { _ in })
    stage.desired = .hidden
    stage.pointerMoved(to: insideZone, zone: zone)
    #expect(await eventually { stage.hoverExpanded })
    stage.pointerMoved(to: CGPoint(x: 0, y: 0), zone: zone)
    try await Task.sleep(for: .milliseconds(250))
    #expect(stage.hoverExpanded)   // still within the 0.5 s leave delay
    #expect(await eventually { !stage.hoverExpanded })
}

@Test func screensRebuiltOnDisplayChange() {
    let screens = [ScreenInfo(id: 1, hasNotch: true, isMain: true), ScreenInfo(id: 2, hasNotch: false, isMain: false)]
    let diff = NotchController.stageIDs(for: screens, current: [1, 3])
    #expect(diff.add == [2])
    #expect(diff.remove == [3])
}

@MainActor
@Test func tearDownStopsPendingHover() async throws {
    var changes: [Bool] = []
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { changes.append($0) })
    stage.desired = .hidden
    stage.pointerMoved(to: insideZone, zone: zone)
    stage.tearDown()
    try await Task.sleep(for: .milliseconds(400))
    #expect(changes.isEmpty)
}

@MainActor
@Test func pinnedPanelIgnoresThePointerLeaving() async throws {
    let stage = NotchStage(screenID: 2, presenter: FakePresenter(), onHoverExpandedChange: { _ in })
    stage.pin()
    #expect(stage.hoverExpanded)
    #expect(stage.pinned)
    stage.pointerMoved(to: insideZone, zone: zone)
    stage.pointerMoved(to: CGPoint(x: 0, y: 0), zone: zone)
    try await Task.sleep(for: .milliseconds(700))
    #expect(stage.hoverExpanded)
    stage.unpin()
    #expect(!stage.hoverExpanded)
    #expect(!stage.pinned)
}
