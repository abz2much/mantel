import SwiftUI

/// What one screen's notch is showing. `.tab` is a monitor's small resting tab.
enum NotchMode: Equatable { case hidden, musicCompact, musicExpanded, idle, idleExpanded, meeting, battery, timerDone, tab }

/// Everything one screen's decision depends on, as plain flags.
struct NotchInputs: Equatable {
    var hasReminder = false
    var musicShowsCard = false
    var screenHasNotch = false
    var hoverExpanded = false
    /// Alerts (battery, meeting, "Time's up") show only on this one screen.
    var isAlertScreen = true
    var timerDoneShowing = false
    var batteryFlashing = false
    var timerRunning = false
    var monitorsEnabled = true
    var tabEnabled = true
    var anyNotchScreen = false
}

/// A screen, reduced to what the decision needs.
struct ScreenInfo: Equatable {
    let id: Int
    let hasNotch: Bool
    let isMain: Bool
}

/// Decides what each screen shows. Alerts: battery flash > meeting > "Time's up", on the alert screen only.
/// Otherwise the notch screen rests as before, and a monitor shows its tab, its panel when hovered, or nothing.
enum NotchDecision {
    static func mode(for i: NotchInputs) -> NotchMode {
        if !i.screenHasNotch && !i.monitorsEnabled {
            // Monitors switched off: only a meeting, and only when there's no notch to show it on.
            return i.hasReminder && !i.anyNotchScreen && i.isAlertScreen ? .meeting : .hidden
        }
        if i.isAlertScreen {
            if i.batteryFlashing { return .battery }
            if i.hasReminder { return .meeting }
            if i.timerDoneShowing { return .timerDone }
        }
        if i.screenHasNotch {
            if i.musicShowsCard { return i.hoverExpanded ? .musicExpanded : .musicCompact }
            // Idle: an empty compact notch, so hovering it can open today's agenda.
            return i.hoverExpanded ? .idleExpanded : .idle
        }
        if i.hoverExpanded { return i.musicShowsCard ? .musicExpanded : .idleExpanded }
        return i.tabEnabled && (i.musicShowsCard || i.timerRunning) ? .tab : .hidden
    }

    /// False when the hover panel must close: a meeting or "Time's up" takes over, or there's nowhere to hover.
    static func keepsHoverExpanded(_ i: NotchInputs) -> Bool {
        if i.isAlertScreen && (i.hasReminder || i.timerDoneShowing) { return false }
        if !i.screenHasNotch && !i.monitorsEnabled { return false }
        return i.hoverExpanded
    }

    /// The one screen that shows alerts: the active app's screen if allowed, else the notch screen,
    /// else (monitors off, lid closed) the main screen, where only meetings will show.
    static func alertScreen(screens: [ScreenInfo], active: Int?, monitorsEnabled: Bool) -> Int? {
        if let active, let screen = screens.first(where: { $0.id == active }), screen.hasNotch || monitorsEnabled {
            return active
        }
        if let notch = screens.first(where: \.hasNotch) { return notch.id }
        return (screens.first(where: \.isMain) ?? screens.first)?.id
    }

    /// The flash and glow take the album's colour on the Music tab of the panel, as the panel's own glow does.
    static func glowColor(content: NotchState.Content, tab: HoverTab, accent: Color?) -> Color {
        (content == .panel && tab == .music ? accent : nil) ?? MantelStyle.glow
    }
}
