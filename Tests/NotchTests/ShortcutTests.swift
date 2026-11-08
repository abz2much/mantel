import AppKit
import Carbon
import Testing
@testable import Notch

@Test func defaultIsControlOptionV() {
    #expect(Shortcut.default == Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .option]))
    #expect(Shortcut.default.display == "⌃⌥V")
}

@Test func displayUsesMacOrder() {
    // macOS always shows ⌃ ⌥ ⇧ ⌘ in that order.
    let s = Shortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control])
    #expect(s.display == "⌃⌥⇧⌘K")
    #expect(Shortcut(keyCode: UInt16(kVK_F5), modifiers: [.command]).display == "⌘F5")
    #expect(Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.option]).display == "⌥Space")
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_1), modifiers: [.control]).display == "⌃1")
}

@Test func needsControlOptionOrCommand() {
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.option]).isAllowed)
    #expect(!Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: []).isAllowed)
    #expect(!Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.shift]).isAllowed)
    #expect(!Shortcut(keyCode: UInt16(kVK_Escape), modifiers: [.command]).isAllowed)   // Esc cancels recording
}

@Test func keepsOnlyShortcutModifiers() {
    // Caps Lock, Fn and the like are dropped.
    let s = Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .capsLock, .function])
    #expect(s.modifiers == [.control])
}

@Test func carbonModifiersMatch() {
    #expect(Shortcut.default.carbonModifiers == UInt32(controlKey | optionKey))
    #expect(Shortcut(keyCode: 0, modifiers: [.command, .shift]).carbonModifiers == UInt32(cmdKey | shiftKey))
}

@MainActor
@Test func shortcutIsSavedAndRestored() {
    let defaults = UserDefaults(suiteName: "test.\(UUID())")!
    let board = NSPasteboard(name: .init("test.\(UUID())"))
    let service = ClipboardService(pasteboard: board, defaults: defaults)
    #expect(service.shortcut == .default)
    service.shortcut = Shortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.control, .shift])
    let again = ClipboardService(pasteboard: board, defaults: defaults)
    #expect(again.shortcut == Shortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.control, .shift]))
}

@Test func commandAloneNeedsAnFKey() {
    // ⌘ or ⌘⇧ with a normal key would override app shortcuts like ⌘V and ⌘Q everywhere.
    #expect(!Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command]).isAllowed)
    #expect(!Shortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.control, .shift]).isAllowed)
    #expect(!Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command]).isAllowed)
    #expect(Shortcut(keyCode: UInt16(kVK_F5), modifiers: [.command]).isAllowed)
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .option]).isAllowed)
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .shift]).isAllowed)
}

@MainActor
@Test func aSavedShortcutThatIsntAllowedFallsBackToDefault() throws {
    let defaults = UserDefaults(suiteName: "test.\(UUID())")!
    defaults.set(try JSONEncoder().encode(Shortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [])), forKey: "clipboardShortcutKeys")
    let service = ClipboardService(pasteboard: NSPasteboard(name: .init("test.\(UUID())")), defaults: defaults)
    #expect(service.shortcut == .default)
}
