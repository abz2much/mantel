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
    let loginItem = LoginItemService()
    private(set) lazy var controller = NotchController(calendar: calendar, music: music, battery: battery,
                                                       clipboard: clipboard, timer: timer)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        music.start()
        battery.start()
        clipboard.start()
        updates.start()
        loginItem.start()
        Task { await calendar.start() }
    }
}

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(calendar: delegate.calendar, music: delegate.music, updates: delegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(calendar: delegate.calendar, music: delegate.music, battery: delegate.battery,
                         clipboard: delegate.clipboard, updates: delegate.updates, loginItem: delegate.loginItem)
        }
    }
}

/// The menu bar menu: anything needing attention, update status, Settings and Quit.
struct MenuContent: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicService
    @ObservedObject var updates: UpdateService

    var body: some View {
        let warnings = MenuWarnings.make(calendarAccess: calendar.hasAccess, musicEnabled: music.musicEnabled,
                                         blockedApps: music.blockedApps)
        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
            switch warning {
            case .calendarAccess:
                Button("⚠︎ Calendar access is off: Open Privacy Settings…") { SystemSettings.open(.calendars) }
            case .automation(let apps):
                Button("⚠︎ \(apps) control is blocked: Open Automation Settings…") { SystemSettings.open(.automation) }
            }
        }
        if !warnings.isEmpty { Divider() }
        Text(UpdateStatusText.line(updates))
        Button("Check for Updates Now") { updates.checkNow() }
            .disabled(updates.status == .checking)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Mantel") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
