import Foundation

struct BatteryReading: Equatable {
    let percent: Int
    let onPower: Bool
}

extension BatteryReading {
    /// From macOS's power source descriptions; nil on a Mac without a built-in battery.
    init?(sources: [[String: Any]], providingType: String) {
        guard let battery = sources.first(where: { $0["Type"] as? String == "InternalBattery" }),
              let current = battery["Current Capacity"] as? Int,
              let max = battery["Max Capacity"] as? Int, max > 0
        else { return nil }
        self.init(percent: Int((Double(current) / Double(max) * 100).rounded()), onPower: providingType == "AC Power")
    }
}

enum BatteryAlert: Equatable {
    case charging(percent: Int)
    case low(percent: Int)

    /// Whether the menu bar switch for this kind of alert is on.
    func isAllowed(charging: Bool, low: Bool) -> Bool {
        switch self {
        case .charging: charging
        case .low: low
        }
    }
}

/// Decides when a battery reading should flash a charging or low-battery alert in the notch.
struct BatteryAlertPolicy {
    /// Battery levels that each warn once per discharge.
    static let lowLevels = [20, 10]
    /// A reconnect sooner than this after the last charging alert (a loose cable) stays quiet.
    static let replugQuietPeriod: TimeInterval = 5

    private var wasOnPower: Bool?
    private var lastChargingAlert: Date?
    private var warnedLevels: Set<Int> = []

    mutating func update(_ reading: BatteryReading, now: Date) -> BatteryAlert? {
        defer { wasOnPower = reading.onPower }

        if reading.onPower {
            warnedLevels = []
            // No alert on the first reading: the app launching while plugged in isn't a plug-in.
            guard wasOnPower == false else { return nil }
            if let last = lastChargingAlert, now.timeIntervalSince(last) < Self.replugQuietPeriod { return nil }
            lastChargingAlert = now
            return .charging(percent: reading.percent)
        }

        let crossed = Self.lowLevels.filter { reading.percent <= $0 && !warnedLevels.contains($0) }
        guard !crossed.isEmpty else { return nil }
        warnedLevels.formUnion(crossed)
        return .low(percent: reading.percent)
    }
}
