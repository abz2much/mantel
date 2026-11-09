import Foundation

/// The two switches for screens without a notch. Both are on by default.
@MainActor
final class MonitorSettings: ObservableObject {
    private static let enabledKey = "monitorsEnabled"
    private static let tabKey = "monitorTabEnabled"
    private let defaults: UserDefaults

    /// "Use Mantel on screens without a notch."
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// "Show a small tab while music or a timer runs."
    @Published var tabEnabled: Bool {
        didSet { defaults.set(tabEnabled, forKey: Self.tabKey) }
    }

    var showsTab: Bool { enabled && tabEnabled }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        tabEnabled = defaults.object(forKey: Self.tabKey) as? Bool ?? true
    }
}
