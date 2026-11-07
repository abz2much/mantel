import Foundation
import IOKit.ps

/// Watches the Mac's battery and reports when a charging or low-battery alert should flash.
@MainActor
final class BatteryService: ObservableObject {
    private static let chargingKey = "batteryChargingAlert"
    private static let lowKey = "batteryLowAlert"

    @Published var chargingAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(chargingAlertEnabled, forKey: Self.chargingKey) }
    }
    @Published var lowAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(lowAlertEnabled, forKey: Self.lowKey) }
    }

    /// Called with each alert that should show, after the menu switches are applied.
    var onAlert: ((BatteryAlert) -> Void)?

    private var policy = BatteryAlertPolicy()
    private var source: CFRunLoopSource?

    init() {
        let defaults = UserDefaults.standard
        chargingAlertEnabled = defaults.object(forKey: Self.chargingKey) as? Bool ?? true
        lowAlertEnabled = defaults.object(forKey: Self.lowKey) as? Bool ?? true
    }

    func start() {
        if Self.fake { playFakeReadings(); return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // macOS calls this on the main run loop whenever a power source changes.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.check() }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        check()
    }

    private func check() {
        guard let reading = Self.read() else { return }
        handle(reading)
    }

    private func handle(_ reading: BatteryReading) {
        guard let alert = policy.update(reading, now: Date()),
              alert.isAllowed(charging: chargingAlertEnabled, low: lowAlertEnabled)
        else { return }
        onAlert?(alert)
    }

    /// NOTCH_FAKE_BATTERY=1: a plug-in after 2 s, then a drop to 20% on battery after 8 s. For trying the flashes.
    private static let fake = ProcessInfo.processInfo.environment["NOTCH_FAKE_BATTERY"] == "1"

    private func playFakeReadings() {
        let script: [(TimeInterval, BatteryReading)] = [
            (0, BatteryReading(percent: 72, onPower: false)),
            (2, BatteryReading(percent: 72, onPower: true)),
            (7, BatteryReading(percent: 21, onPower: false)),
            (8, BatteryReading(percent: 20, onPower: false)),
        ]
        for (delay, reading) in script {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(reading) }
            }
        }
    }

    private static func read() -> BatteryReading? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        let sources = list.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }
        let providing = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
        return BatteryReading(sources: sources, providingType: providing)
    }
}
