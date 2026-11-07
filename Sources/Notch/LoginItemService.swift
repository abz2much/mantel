import Foundation
import ServiceManagement

/// Open at Login, through macOS's own login items (System Settings → General → Login Items).
@MainActor
final class LoginItemService: ObservableObject {
    private static let defaultAppliedKey = "openAtLoginDefaultApplied"

    @Published private(set) var enabled = false
    /// macOS wants the user to allow it in System Settings before it takes effect.
    @Published private(set) var needsApproval = false
    @Published private(set) var problem: String?

    init() { refresh() }

    /// Switches Open at Login on the first time an installed copy opens; after that it's left to the user.
    func start() {
        let installed = UpdateRules.canSelfUpdate(appURL: Bundle.main.bundleURL,
                                                  home: FileManager.default.homeDirectoryForCurrentUser)
        let done = UserDefaults.standard.bool(forKey: Self.defaultAppliedKey)
        if LoginItemRules.registerByDefault(alreadyDone: done, isInstalled: installed) {
            setEnabled(true)
            UserDefaults.standard.set(true, forKey: Self.defaultAppliedKey)
        }
        refresh()
    }

    func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = nil
        } catch {
            problem = on ? "Couldn't add Mantel to Login Items" : "Couldn't remove Mantel from Login Items"
        }
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
}
