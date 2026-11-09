import Foundation
import Testing
@testable import Mantel

private let earlier = Date(timeIntervalSince1970: 1_800_000_000)
private let now = earlier.addingTimeInterval(60)

private func song(_ title: String, _ state: TrackInfo.PlayState) -> TrackInfo {
    TrackInfo(state: state, title: title, artist: "Artist", duration: 200, artworkKey: nil)
}

@Test func pressingPlayStartsTheClock() {
    let before = PlayerActivity(playingSince: nil, lastActive: earlier)
    let after = before.updated(from: song("A", .paused), to: song("A", .playing), now: now)
    #expect(after == PlayerActivity(playingSince: now, lastActive: now))
}

@Test func nextSongWhilePlayingKeepsWhenPlaybackStarted() {
    // Otherwise, with both apps playing, the card would jump on every song change.
    let before = PlayerActivity(playingSince: earlier, lastActive: earlier)
    let after = before.updated(from: song("A", .playing), to: song("B", .playing), now: now)
    #expect(after.playingSince == earlier)
}

@Test func pausingCountsAsUse() {
    let before = PlayerActivity(playingSince: earlier, lastActive: earlier)
    let after = before.updated(from: song("A", .playing), to: song("A", .paused), now: now)
    #expect(after == PlayerActivity(playingSince: nil, lastActive: now))
}

@Test func appOpeningWithAPausedSongIsNotUse() {
    // Spotify opens with last session's song paused; that isn't the user picking it.
    let after = PlayerActivity(playingSince: nil, lastActive: nil).updated(from: nil, to: song("A", .paused), now: now)
    #expect(after == PlayerActivity(playingSince: nil, lastActive: .distantPast))
}

@Test func firstSeenPlayingCountsAsStarted() {
    let after = PlayerActivity(playingSince: nil, lastActive: nil).updated(from: nil, to: song("A", .playing), now: now)
    #expect(after == PlayerActivity(playingSince: now, lastActive: now))
}

@Test func trackGoneClearsBoth() {
    let before = PlayerActivity(playingSince: earlier, lastActive: earlier)
    #expect(before.updated(from: song("A", .playing), to: nil, now: now) == PlayerActivity(playingSince: nil, lastActive: nil))
}
