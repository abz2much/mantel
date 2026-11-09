import Foundation
import Testing
@testable import Mantel

@MainActor
@Test func remindersAreOffUntilTurnedOn() {
    let defaults = UserDefaults(suiteName: "test.\(UUID())")!
    let service = RemindersService(defaults: defaults)
    #expect(!service.enabled)
    #expect(service.items.isEmpty)
}

@MainActor
@Test func listChoicesAreRemembered() {
    let defaults = UserDefaults(suiteName: "test.\(UUID())")!
    let service = RemindersService(defaults: defaults)
    service.setSelected(false, listID: "work")
    #expect(!service.isSelected(listID: "work"))
    #expect(service.isSelected(listID: "home"))   // new lists are shown by default
    let again = RemindersService(defaults: defaults)
    #expect(!again.isSelected(listID: "work"))
}
