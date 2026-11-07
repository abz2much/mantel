import Foundation
import Testing
@testable import Notch

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
private func battery(_ percent: Int) -> BatteryReading { BatteryReading(percent: percent, onPower: false) }
private func power(_ percent: Int) -> BatteryReading { BatteryReading(percent: percent, onPower: true) }

// MARK: Charging

@Test func pluggingInShowsChargingAlertWithLevel() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(72), now: at(0))
    #expect(policy.update(power(72), now: at(10)) == .charging(percent: 72))
}

@Test func launchingWhilePluggedInShowsNothing() {
    var policy = BatteryAlertPolicy()
    #expect(policy.update(power(72), now: at(0)) == nil)
}

@Test func stayingPluggedInShowsNothingMore() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(72), now: at(0))
    _ = policy.update(power(72), now: at(10))
    #expect(policy.update(power(73), now: at(70)) == nil)
}

@Test func unpluggingShowsNothing() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(power(72), now: at(0))
    #expect(policy.update(battery(72), now: at(10)) == nil)
}

@Test func looseCableReconnectingWithinFiveSecondsShowsOnce() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(72), now: at(0))
    _ = policy.update(power(72), now: at(10))
    _ = policy.update(battery(72), now: at(11))
    #expect(policy.update(power(72), now: at(13)) == nil)
}

@Test func pluggingInAgainAfterFiveSecondsShowsAgain() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(72), now: at(0))
    _ = policy.update(power(72), now: at(10))
    _ = policy.update(battery(72), now: at(12))
    #expect(policy.update(power(72), now: at(16)) == .charging(percent: 72))
}

// MARK: Low battery

@Test func droppingTo20OnBatteryWarns() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(21), now: at(0))
    #expect(policy.update(battery(20), now: at(60)) == .low(percent: 20))
}

@Test func lowWarningShowsOncePerLevel() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(21), now: at(0))
    _ = policy.update(battery(20), now: at(60))
    #expect(policy.update(battery(19), now: at(120)) == nil)
}

@Test func droppingTo10WarnsAgain() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(21), now: at(0))
    _ = policy.update(battery(20), now: at(60))
    _ = policy.update(battery(11), now: at(120))
    #expect(policy.update(battery(10), now: at(180)) == .low(percent: 10))
}

@Test func skippingPastBothLevelsWarnsOnce() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(25), now: at(0))
    #expect(policy.update(battery(9), now: at(60)) == .low(percent: 9))
    #expect(policy.update(battery(8), now: at(120)) == nil)
}

@Test func noLowWarningWhileOnPower() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(power(21), now: at(0))
    #expect(policy.update(power(20), now: at(60)) == nil)
}

@Test func launchingOnLowBatteryWarns() {
    var policy = BatteryAlertPolicy()
    #expect(policy.update(battery(15), now: at(0)) == .low(percent: 15))
}

@Test func chargingResetsLowWarnings() {
    var policy = BatteryAlertPolicy()
    _ = policy.update(battery(21), now: at(0))
    _ = policy.update(battery(20), now: at(60))
    _ = policy.update(power(25), now: at(120))
    _ = policy.update(battery(25), now: at(180))
    #expect(policy.update(battery(20), now: at(240)) == .low(percent: 20))
}
