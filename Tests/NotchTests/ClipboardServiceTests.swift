import AppKit
import Testing
@testable import Notch

/// Uses a private, uniquely named pasteboard: the real clipboard is never touched.
@MainActor
private func makeService() -> (ClipboardService, NSPasteboard) {
    let board = NSPasteboard(name: NSPasteboard.Name("notch-test-\(UUID().uuidString)"))
    return (ClipboardService(pasteboard: board), board)
}

@MainActor @Test func aNewTextCopyIsRecorded() {
    let (service, board) = makeService()
    board.clearContents()
    board.setString("hello", forType: .string)
    service.check()
    #expect(service.items.map(\.text) == ["hello"])
    board.releaseGlobally()
}

@MainActor @Test func aPasswordManagerCopyIsNotRecorded() {
    let (service, board) = makeService()
    board.clearContents()
    board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
    board.setString("hunter2", forType: .string)
    service.check()
    #expect(service.items.isEmpty)
    board.releaseGlobally()
}

@MainActor @Test func copyingAnItemPutsItBackOnTheClipboard() throws {
    let (service, board) = makeService()
    board.clearContents(); board.setString("first", forType: .string); service.check()
    board.clearContents(); board.setString("second", forType: .string); service.check()
    let first = try #require(service.items.last)
    service.copy(first)
    #expect(board.string(forType: .string) == "first")
    #expect(service.items.map(\.text) == ["first", "second"])
    board.releaseGlobally()
}

@MainActor @Test func aTemporaryCopyIsNotRecorded() {
    let (service, board) = makeService()
    board.clearContents()
    board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
    board.setString("123456", forType: .string)
    service.check()
    #expect(service.items.isEmpty)
    board.releaseGlobally()
}

@MainActor @Test func whatWasCopiedBeforeStartIsNotRecorded() {
    let board = NSPasteboard(name: NSPasteboard.Name("notch-test-\(UUID().uuidString)"))
    board.clearContents(); board.setString("earlier", forType: .string)
    let service = ClipboardService(pasteboard: board)
    service.check()
    #expect(service.items.isEmpty)
    board.releaseGlobally()
}

@MainActor @Test func turningOffClearsAndTurningOnIgnoresCopiesMadeWhileOff() {
    let (service, board) = makeService()
    let wasEnabled = service.enabled
    defer { service.enabled = wasEnabled }   // the switch is saved; put it back
    board.clearContents(); board.setString("kept", forType: .string); service.check()
    service.enabled = false
    #expect(service.items.isEmpty)
    board.clearContents(); board.setString("while off", forType: .string)
    service.enabled = true
    service.check()
    #expect(service.items.isEmpty)
    board.releaseGlobally()
}

@MainActor @Test func clearEmptiesTheList() {
    let (service, board) = makeService()
    board.clearContents(); board.setString("a", forType: .string); service.check()
    service.clear()
    #expect(service.items.isEmpty)
    board.releaseGlobally()
}
