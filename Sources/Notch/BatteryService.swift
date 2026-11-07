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
    private var wasOnPower: Bool?
    private var settleTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        chargingAlertEnabled = defaults.object(forKey: Self.chargingKey) as? Bool ?? true
        lowAlertEnabled = defaults.object(forKey: Self.lowKey) as? Bool ?? true
    }

    /// Starts watching. The service must live as long as the app: the callback holds it unretained.
    func start() {
        guard source == nil else { return }
        if Self.fake { playFakeReadings(); return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // macOS calls this on the main run loop whenever a power source changes.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.check() }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        // Common modes, so a plug-in while the menu bar menu is open still flashes straight away.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        check()
    }

    private func check() {
        guard !Self.fake, let reading = Self.read() else { return }
        handle(reading)
    }

    private func handle(_ reading: BatteryReading) {
        // After an unplug the policy waits for the cable to settle; look again once it has,
        // as macOS may not report anything new for minutes.
        if wasOnPower == true, !reading.onPower {
            settleTimer?.invalidate()
            let timer = Timer(timeInterval: BatteryAlertPolicy.replugQuietPeriod + 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            settleTimer = timer
        }
        wasOnPower = reading.onPower

        guard let alert = policy.update(reading, now: Date()),
              alert.isAllowed(charging: chargingAlertEnabled, low: lowAlertEnabled)
        else { return }
        onAlert?(alert)
    }

    /// NOTCH_FAKE_BATTERY=1: a plug-in after 2 s, an unplug at 21% after 7 s, then a drop to 20% after 13 s. For trying the flashes.
    private static let fake = ProcessInfo.processInfo.environment["NOTCH_FAKE_BATTERY"] == "1"

    private func playFakeReadings() {
        let script: [(TimeInterval, BatteryReading)] = [
            (0, BatteryReading(percent: 72, onPower: false)),
            (2, BatteryReading(percent: 72, onPower: true)),
            (7, BatteryReading(percent: 21, onPower: false)),
            (13, BatteryReading(percent: 20, onPower: false)),
        ]
        handle(script[0].1)
        for (delay, reading) in script.dropFirst() {
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
