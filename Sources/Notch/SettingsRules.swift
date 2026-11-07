/// Open at Login is switched on once, the first time an installed copy opens; after that it's the user's
/// choice. Copies built from source never add themselves.
enum LoginItemRules {
    static func registerByDefault(alreadyDone: Bool, isInstalled: Bool) -> Bool {
        isInstalled && !alreadyDone
    }
}

/// Something that needs the user's attention, shown at the top of the menu.
enum MenuWarning: Equatable {
    case calendarAccess
    /// Spotify and/or Music control was refused (their names).
    case automation(String)
}

enum MenuWarnings {
    static func make(calendarAccess: Bool, musicEnabled: Bool, blockedApps: [String]) -> [MenuWarning] {
        var warnings: [MenuWarning] = []
        if !calendarAccess { warnings.append(.calendarAccess) }
        if musicEnabled, !blockedApps.isEmpty { warnings.append(.automation(blockedApps.joined(separator: " and "))) }
        return warnings
    }
}
