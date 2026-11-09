import Foundation
import Testing
@testable import Mantel

// Keys as macOS's power source info reports them (IOPSKeys.h).
private func source(current: Int, max: Int, type: String = "InternalBattery") -> [String: Any] {
    ["Current Capacity": current, "Max Capacity": max, "Type": type]
}

@Test func readsPercentAndMainsPower() {
    let reading = BatteryReading(sources: [source(current: 72, max: 100)], providingType: "AC Power")
    #expect(reading == BatteryReading(percent: 72, onPower: true))
}

@Test func readsBatteryPower() {
    let reading = BatteryReading(sources: [source(current: 40, max: 100)], providingType: "Battery Power")
    #expect(reading == BatteryReading(percent: 40, onPower: false))
}

@Test func scalesCapacityThatIsNotAPercentage() {
    let reading = BatteryReading(sources: [source(current: 3600, max: 5000)], providingType: "Battery Power")
    #expect(reading?.percent == 72)
}

@Test func ignoresNonInternalSources() {
    // A UPS reports as a power source too; only the Mac's own battery counts.
    let ups = source(current: 10, max: 100, type: "UPS")
    let reading = BatteryReading(sources: [ups, source(current: 80, max: 100)], providingType: "AC Power")
    #expect(reading?.percent == 80)
}

@Test func macWithoutBatteryHasNoReading() {
    #expect(BatteryReading(sources: [], providingType: "AC Power") == nil)
}

@Test func zeroMaxCapacityHasNoReading() {
    #expect(BatteryReading(sources: [source(current: 0, max: 0)], providingType: "AC Power") == nil)
}

@Test func switchedOffAlertKindsAreDropped() {
    #expect(BatteryAlert.charging(percent: 50).isAllowed(charging: false, low: true) == false)
    #expect(BatteryAlert.charging(percent: 50).isAllowed(charging: true, low: false) == true)
    #expect(BatteryAlert.low(percent: 20).isAllowed(charging: true, low: false) == false)
    #expect(BatteryAlert.low(percent: 20).isAllowed(charging: false, low: true) == true)
}
