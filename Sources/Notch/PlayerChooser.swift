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

/// When one app last started playing and when it was last used, kept up to date as its track changes.
struct PlayerActivity: Equatable {
    var playingSince: Date?
    var lastActive: Date?

    /// Only pressing play counts as starting (not the next song coming on), and an app opening
    /// with last session's song paused doesn't count as being used.
    func updated(from old: TrackInfo?, to new: TrackInfo?, now: Date) -> PlayerActivity {
        guard let new else { return PlayerActivity(playingSince: nil, lastActive: nil) }
        guard new != old else { return self }
        let isPlaying = new.state == .playing
        return PlayerActivity(
            playingSince: isPlaying ? (old?.state == .playing ? playingSince : now) : nil,
            lastActive: old == nil && !isPlaying ? .distantPast : now
        )
    }
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
