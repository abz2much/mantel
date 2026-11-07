import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendar = CalendarService()
    let spotify = SpotifyService()
    let battery = BatteryService()
    private(set) lazy var controller = NotchController(calendar: calendar, spotify: spotify, battery: battery)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        spotify.start()
        battery.start()
        Task { await calendar.start() }
    }
}

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "calendar.badge.clock") {
            MenuContent(calendar: delegate.calendar, spotify: delegate.spotify, battery: delegate.battery)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var spotify: SpotifyService
    @ObservedObject var battery: BatteryService

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
        Toggle("Show music card", isOn: $spotify.musicEnabled)
        Toggle("Show album art", isOn: $spotify.showAlbumArt)
            .disabled(!spotify.musicEnabled)
        if spotify.musicEnabled && spotify.permissionDenied {
            Text("Spotify control blocked: Automation permission denied")
            Button("Open Automation Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
        }
        Divider()
        Toggle("Charging animation", isOn: $battery.chargingAlertEnabled)
        Toggle("Low battery alert", isOn: $battery.lowAlertEnabled)
        Divider()
        Button("Quit Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
