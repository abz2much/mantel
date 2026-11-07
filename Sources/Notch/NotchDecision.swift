import SwiftUI

/// What the notch is showing.
enum NotchMode: Equatable { case hidden, musicCompact, musicExpanded, idle, idleExpanded, meeting, battery, timerDone }

/// Everything the decision depends on, as plain flags.
struct NotchInputs: Equatable {
    var hasReminder = false
    var musicShowsCard = false
    var screenHasNotch = false
    var hoverExpanded = false
    var peeking = false
    var timerDoneShowing = false
    var batteryFlashing = false
}

/// Decides what the notch shows: battery flash > meeting > "Time's up" > music > idle.
enum NotchDecision {
    static func mode(for i: NotchInputs) -> NotchMode {
        if i.batteryFlashing { return .battery }
        if i.hasReminder { return .meeting }
        if i.timerDoneShowing { return .timerDone }
        if i.musicShowsCard {
            if i.screenHasNotch { return i.hoverExpanded ? .musicExpanded : .musicCompact }
            return i.peeking ? .musicExpanded : .hidden
        }
        // Idle: an empty compact notch, so hovering it can open today's agenda.
        if i.screenHasNotch { return i.hoverExpanded ? .idleExpanded : .idle }
        return .hidden
    }

    /// False when the hover panel must close: a meeting or "Time's up" takes over, or there's nowhere to hover.
    static func keepsHoverExpanded(_ i: NotchInputs) -> Bool {
        if i.hasReminder || i.timerDoneShowing { return false }
        if !i.musicShowsCard && !i.screenHasNotch { return false }
        return i.hoverExpanded
    }

    /// The flash and glow take the album's colour on the Music tab of the panel, as the panel's own glow does.
    static func glowColor(content: NotchState.Content, tab: HoverTab, accent: Color?) -> Color {
        (content == .panel && tab == .music ? accent : nil) ?? MantelStyle.glow
    }
}
