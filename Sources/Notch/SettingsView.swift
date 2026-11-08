import AppKit
import SwiftUI

/// The Settings window (⌘,): General, Features and Calendars.
struct SettingsView: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var reminders: RemindersService
    @ObservedObject var music: MusicService
    @ObservedObject var battery: BatteryService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var updates: UpdateService
    @ObservedObject var loginItem: LoginItemService
    @ObservedObject var monitors: MonitorSettings

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            features.tabItem { Label("Features", systemImage: "square.grid.2x2") }
            calendars.tabItem { Label("Calendars", systemImage: "calendar") }
        }
        .frame(width: 480)
        .onAppear { loginItem.refresh() }
        // Coming back from System Settings (approving or removing the login item) refreshes the switch.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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
            Section("Monitors") {
                Toggle("Use Mantel on screens without a notch", isOn: $monitors.enabled)
                Toggle("Show a small tab while music or a timer runs", isOn: $monitors.tabEnabled)
                    .padding(.leading, 16)
                    .disabled(!monitors.enabled)
            }
            Section("Clipboard") {
                Toggle("Clipboard history", isOn: $clipboard.enabled)
                Toggle("Open with a shortcut", isOn: $clipboard.shortcutEnabled)
                    .padding(.leading, 16)
                    .disabled(!clipboard.enabled)
                HStack(alignment: .top) {
                    Text("Shortcut")
                    Spacer()
                    ShortcutRecorder(clipboard: clipboard)
                }
                .padding(.leading, 32)
                .disabled(!clipboard.opensWithShortcut && !clipboard.recordingShortcut)
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
            Section("Reminders") {
                Toggle("Show reminders in Today", isOn: $reminders.enabled)
                Text("Overdue and today's reminders appear under your meetings. Tick one to mark it done.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if reminders.enabled, reminders.asked, !reminders.hasAccess {
                approvalRow("Mantel can't read your reminders.", button: "Open Privacy Settings…") {
                    SystemSettings.open(.reminders)
                }
            } else if reminders.enabled, reminders.hasAccess {
                Section("Show reminders from") {
                    ForEach(reminders.lists, id: \.calendarIdentifier) { list in
                        Toggle("\(list.title) (\(list.source.title))", isOn: Binding(
                            get: { reminders.isSelected(listID: list.calendarIdentifier) },
                            set: { reminders.setSelected($0, listID: list.calendarIdentifier) }
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
        line(version: updates.currentVersion, status: updates.status)
    }

    static func line(version current: AppVersion?, status: UpdateService.Status) -> String {
        let version = current.map { "Mantel \($0)" } ?? "Mantel"
        switch status {
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
    enum Pane { case calendars, reminders, automation }

    static func open(_ pane: Pane) {
        let anchor = switch pane {
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .automation: "Privacy_Automation"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
