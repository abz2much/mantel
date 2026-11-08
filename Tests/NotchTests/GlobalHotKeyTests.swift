import Carbon
import Testing
@testable import Notch

/// ⌃⌥⇧⌘F19: nothing else uses it, so the test never clashes with a running Mantel.
private let keyCode = UInt32(kVK_F19)
private let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

@MainActor
@Test func aTakenShortcutLeavesNothingBehind() {
    let first = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {}
    first.register()
    #expect(first.isRegistered)
    first.register()   // a second call changes nothing
    #expect(first.isRegistered)

    let second = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {}
    second.register()   // already taken
    #expect(!second.isRegistered)
    #expect(!second.hasHandler)

    first.unregister()
    #expect(!first.isRegistered)
    #expect(!first.hasHandler)
}
