import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendar = CalendarService()
    let reminders = RemindersService()
    let music = MusicService()
    let battery = BatteryService()
    let clipboard = ClipboardService()
    let updates = UpdateService()
    let timer = TimerService()
    let loginItem = LoginItemService()
    let monitors = MonitorSettings()
    private(set) lazy var controller = NotchController(calendar: calendar, reminders: reminders, music: music, battery: battery,
                                                       clipboard: clipboard, timer: timer, monitors: monitors)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        music.start()
        battery.start()
        clipboard.start()
        updates.start()
        loginItem.start()
        Task {
            await calendar.start()
            await reminders.start()   // only asks for access if reminders were turned on in Settings
        }
    }
}

@main
struct MantelApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(calendar: delegate.calendar, music: delegate.music, updates: delegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(calendar: delegate.calendar, reminders: delegate.reminders, music: delegate.music, battery: delegate.battery,
                         clipboard: delegate.clipboard, updates: delegate.updates, loginItem: delegate.loginItem,
                         monitors: delegate.monitors)
        }
    }
}

/// The menu bar menu: anything needing attention, update status, Settings and Quit.
struct MenuContent: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicService
    @ObservedObject var updates: UpdateService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let warnings = MenuWarnings.make(calendarAccess: calendar.hasAccess, musicEnabled: music.musicEnabled,
                                         blockedApps: music.blockedApps)
        ForEach(warnings, id: \.self) { warning in
            switch warning {
            case .calendarAccess:
                Text("⚠︎ Calendar access is off")
                Button("Open Privacy Settings…") { SystemSettings.open(.calendars) }
            case .automation(let apps):
                Text("⚠︎ \(apps) control is blocked")
                Button("Open Automation Settings…") { SystemSettings.open(.automation) }
            }
        }
        if !warnings.isEmpty { Divider() }
        Text(UpdateStatusText.line(updates))
        Button("Check for Updates Now") { updates.checkNow() }
            .disabled(updates.status == .checking)
        Divider()
        Button("Settings…") {
            // A menu bar app isn't frontmost: bring Mantel forward so Settings never opens behind other windows.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Mantel") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
