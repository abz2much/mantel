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
