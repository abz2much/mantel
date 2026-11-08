import Testing
@testable import Notch

private func press(_ key: ClipboardKeys.Key, selection: Int = 0, count: Int = 5) -> ClipboardKeys.Result {
    ClipboardKeys.handle(key, selection: selection, count: count)
}

@Test func arrowsMoveTheSelectionAndStopAtTheEnds() {
    #expect(press(.down, selection: 0) == .select(1))
    #expect(press(.down, selection: 4) == .select(4))
    #expect(press(.up, selection: 2) == .select(1))
    #expect(press(.up, selection: 0) == .select(0))
}

@Test func returnCopiesTheSelectedItem() {
    #expect(press(.enter, selection: 3) == .copy(3))
}

@Test func digitsCopyThatItemDirectly() {
    #expect(press(.digit(1)) == .copy(0))
    #expect(press(.digit(5)) == .copy(4))
    #expect(press(.digit(6)) == .pass)      // only five items
}

@Test func escapeCloses() {
    #expect(press(.escape) == .close)
}

@Test func emptyListOnlyCloses() {
    #expect(press(.down, count: 0) == .pass)
    #expect(press(.enter, count: 0) == .close)
    #expect(press(.digit(1), count: 0) == .pass)
    #expect(press(.escape, count: 0) == .close)
}

@Test func keyCodesMapToKeys() {
    #expect(ClipboardKeys.Key(keyCode: 125, characters: nil) == .down)
    #expect(ClipboardKeys.Key(keyCode: 126, characters: nil) == .up)
    #expect(ClipboardKeys.Key(keyCode: 36, characters: "\r") == .enter)
    #expect(ClipboardKeys.Key(keyCode: 76, characters: "\u{3}") == .enter)
    #expect(ClipboardKeys.Key(keyCode: 53, characters: nil) == .escape)
    #expect(ClipboardKeys.Key(keyCode: 18, characters: "1") == .digit(1))
    #expect(ClipboardKeys.Key(keyCode: 0, characters: "a") == nil)
    #expect(ClipboardKeys.Key(keyCode: 29, characters: "0") == nil)   // 0 isn't an item number
}

@Test func onAnotherTabOnlyEscapeWorks() {
    #expect(ClipboardKeys.handle(.enter, selection: 0, count: 5, onClipboardTab: false) == .pass)
    #expect(ClipboardKeys.handle(.digit(1), selection: 0, count: 5, onClipboardTab: false) == .pass)
    #expect(ClipboardKeys.handle(.down, selection: 0, count: 5, onClipboardTab: false) == .pass)
    #expect(ClipboardKeys.handle(.escape, selection: 0, count: 5, onClipboardTab: false) == .close)
}
