import Foundation

/// What the chooser needs to know about one music app.
struct PlayerSnapshot: Equatable {
    let hasTrack: Bool
    let isPlaying: Bool
    /// When it last went from not playing to playing (or changed song while playing).
    let playingSince: Date?
    /// When its track or play state last changed.
    let lastActive: Date?
}

/// Decides which music app the card shows.
enum PlayerChooser {
    /// Playing beats paused; among playing apps the latest to start wins; among paused ones the last used.
    static func pick(_ players: [PlayerSnapshot]) -> Int? {
        let withTrack = players.indices.filter { players[$0].hasTrack }
        let playing = withTrack.filter { players[$0].isPlaying }
        if let latest = playing.max(by: { (players[$0].playingSince ?? .distantPast) < (players[$1].playingSince ?? .distantPast) }) {
            return latest
        }
        return withTrack.max { (players[$0].lastActive ?? .distantPast) < (players[$1].lastActive ?? .distantPast) }
    }
}
