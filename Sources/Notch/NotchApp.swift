import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendar = CalendarService()
    let spotify = SpotifyService()
    private(set) lazy var controller = NotchController(calendar: calendar, spotify: spotify)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        spotify.start()
        Task { await calendar.start() }
    }
}

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "calendar.badge.clock") {
            MenuContent(calendar: delegate.calendar, spotify: delegate.spotify)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var spotify: SpotifyService

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
        Button("Quit Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
