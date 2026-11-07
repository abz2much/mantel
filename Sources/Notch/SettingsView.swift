import AppKit
import SwiftUI

/// The Settings window (⌘,): General, Features and Calendars.
struct SettingsView: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicService
    @ObservedObject var battery: BatteryService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var updates: UpdateService
    @ObservedObject var loginItem: LoginItemService

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            features.tabItem { Label("Features", systemImage: "square.grid.2x2") }
            calendars.tabItem { Label("Calendars", systemImage: "calendar") }
        }
        .frame(width: 480)
        .onAppear {
            // A menu bar app isn't frontmost; bring the window forward so it doesn't open behind others.
            NSApp.activate(ignoringOtherApps: true)
            loginItem.refresh()
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    approvalRow("Allow Mantel in Login Items to open it at login.", button: "Open Login Items…") {
                        loginItem.openLoginItemsSettings()
                    }
                }
                if let problem = loginItem.problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Updates") {
                Toggle("Install Updates Automatically", isOn: $updates.autoInstall)
                HStack {
                    Text(UpdateStatusText.line(updates))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updates.checkNow() }
                        .disabled(updates.status == .checking)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var features: some View {
        Form {
            Section("Music") {
                Toggle("Show music card", isOn: $music.musicEnabled)
                Toggle("Show album art", isOn: $music.showAlbumArt)
                    .disabled(!music.musicEnabled)
                if music.musicEnabled, !music.blockedApps.isEmpty {
                    approvalRow("\(music.blockedApps.joined(separator: " and ")) control is blocked.", button: "Open Automation Settings…") {
                        SystemSettings.open(.automation)
                    }
                }
            }
            Section("Battery") {
                Toggle("Charging animation", isOn: $battery.chargingAlertEnabled)
                Toggle("Low battery alert", isOn: $battery.lowAlertEnabled)
            }
            Section("Clipboard") {
                Toggle("Clipboard history", isOn: $clipboard.enabled)
                HStack {
                    Text("Kept in memory only, never saved.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History") { clipboard.clear() }
                        .disabled(!clipboard.enabled || clipboard.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var calendars: some View {
        Form {
            if !calendar.hasAccess {
                approvalRow("Mantel can't read your calendars, so there are no meeting reminders.", button: "Open Privacy Settings…") {
                    SystemSettings.open(.calendars)
                }
            } else {
                Section("Show meetings from") {
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                        Toggle("\(cal.title) (\(cal.source.title))", isOn: Binding(
                            get: { calendar.isSelected(cal) },
                            set: { calendar.setSelected($0, for: cal) }
                        ))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func approvalRow(_ message: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
            Button(button, action: action)
        }
    }
}

/// The version-and-status line used by the menu and Settings.
enum UpdateStatusText {
    @MainActor
    static func line(_ updates: UpdateService) -> String {
        let version = updates.currentVersion.map { "Mantel \($0)" } ?? "Mantel"
        switch updates.status {
        case .notChecked: return version
        case .checking: return "\(version): checking for updates…"
        case .upToDate: return "\(version): up to date"
        case .installing(let new): return "Installing Mantel \(new)…"
        case .available(let new): return "Mantel \(new) is available"
        case .unavailable(let reason), .failed(let reason): return "\(version): \(reason)"
        }
    }
}

enum SystemSettings {
    enum Pane { case calendars, automation }

    static func open(_ pane: Pane) {
        let anchor = switch pane {
        case .calendars: "Privacy_Calendars"
        case .automation: "Privacy_Automation"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
