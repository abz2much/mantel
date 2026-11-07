import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendar = CalendarService()
    let music = MusicService()
    let battery = BatteryService()
    let clipboard = ClipboardService()
    let updates = UpdateService()
    let timer = TimerService()
    private(set) lazy var controller = NotchController(calendar: calendar, music: music, battery: battery,
                                                       clipboard: clipboard, timer: timer)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if renameFromNotch() { return }
        controller.start()
        music.start()
        battery.start()
        clipboard.start()
        updates.start()
        Task { await calendar.start() }
    }

    /// The app used to be called Notch. An installed Notch.app (updated from before the rename) moves
    /// itself to Mantel.app once and reopens from there. Its ID and signature are unchanged, so macOS
    /// keeps its permissions. Returns true if it's reopening.
    private func renameFromNotch() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let target = UpdateRules.renameTarget(appURL: Bundle.main.bundleURL, home: home) else { return false }
        do {
            try FileManager.default.moveItem(at: Bundle.main.bundleURL, to: target)
        } catch {
            return false   // keep running as Notch.app; nothing is lost
        }
        UpdateService.relaunch(target)
        return true
    }
}

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(calendar: delegate.calendar, music: delegate.music, battery: delegate.battery,
                        clipboard: delegate.clipboard, updates: delegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicService
    @ObservedObject var battery: BatteryService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var updates: UpdateService

    var body: some View {
        if !calendar.hasAccess {
            Text("Calendar access not granted")
            Button("Open Privacy Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
        } else {
            Text("Calendars")
            ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                Toggle("\(cal.title) (\(cal.source.title))", isOn: Binding(
                    get: { calendar.isSelected(cal) },
                    set: { calendar.setSelected($0, for: cal) }
                ))
            }
        }
        Divider()
        Toggle("Show music card", isOn: $music.musicEnabled)
        Toggle("Show album art", isOn: $music.showAlbumArt)
            .disabled(!music.musicEnabled)
        if music.musicEnabled && !music.blockedApps.isEmpty {
            Text("\(music.blockedApps.joined(separator: " and ")) control blocked: Automation permission denied")
            Button("Open Automation Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
        }
        Divider()
        Toggle("Charging animation", isOn: $battery.chargingAlertEnabled)
        Toggle("Low battery alert", isOn: $battery.lowAlertEnabled)
        Divider()
        Toggle("Clipboard history", isOn: $clipboard.enabled)
        Button("Clear Clipboard History") { clipboard.clear() }
            .disabled(!clipboard.enabled || clipboard.items.isEmpty)
        Divider()
        Text(updateLine)
        Toggle("Install Updates Automatically", isOn: $updates.autoInstall)
        Button("Check for Updates Now") { updates.checkNow() }
            .disabled(updates.status == .checking)
        Divider()
        Button("Quit Mantel") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var updateLine: String {
        let version = updates.currentVersion.map { "Mantel \($0)" } ?? "Mantel"
        switch updates.status {
        case .notChecked: return version
        case .checking: return "\(version): checking for updates…"
        case .upToDate: return "\(version): up to date"
        case .installing(let new): return "Installing Mantel \(new)…"
        case .available(let new): return "Mantel \(new) is available: choose Check for Updates Now"
        case .unavailable(let reason), .failed(let reason): return "\(version): \(reason)"
        }
    }
}
