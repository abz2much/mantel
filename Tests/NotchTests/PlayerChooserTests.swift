import Foundation
import Testing
@testable import Notch

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

private func playing(since: TimeInterval) -> PlayerSnapshot {
    PlayerSnapshot(hasTrack: true, isPlaying: true, playingSince: at(since), lastActive: at(since))
}
private func paused(lastActive: TimeInterval) -> PlayerSnapshot {
    PlayerSnapshot(hasTrack: true, isPlaying: false, playingSince: nil, lastActive: at(lastActive))
}
private let nothing = PlayerSnapshot(hasTrack: false, isPlaying: false, playingSince: nil, lastActive: nil)

@Test func noPlayerWithATrackPicksNone() {
    #expect(PlayerChooser.pick([nothing, nothing]) == nil)
}

@Test func theOnlyPlayerWithATrackIsPicked() {
    #expect(PlayerChooser.pick([nothing, paused(lastActive: 10)]) == 1)
}

@Test func playingBeatsPaused() {
    // Spotify paused more recently than Apple Music started playing: playing still wins.
    #expect(PlayerChooser.pick([paused(lastActive: 50), playing(since: 10)]) == 1)
}

@Test func whenBothPlayTheLatestToStartWins() {
    #expect(PlayerChooser.pick([playing(since: 10), playing(since: 20)]) == 1)
    #expect(PlayerChooser.pick([playing(since: 20), playing(since: 10)]) == 0)
}

@Test func whenBothArePausedTheLastUsedWins() {
    #expect(PlayerChooser.pick([paused(lastActive: 30), paused(lastActive: 10)]) == 0)
    #expect(PlayerChooser.pick([paused(lastActive: 10), paused(lastActive: 30)]) == 1)
}
