import Foundation
import Testing
@testable import Notch

/// An AppleScript list reply, as the state scripts return it.
private func reply(_ items: [Any]) -> NSAppleEventDescriptor {
    let list = NSAppleEventDescriptor.list()
    for item in items {
        let d: NSAppleEventDescriptor = switch item {
        case let s as String: NSAppleEventDescriptor(string: s)
        case let n as Double: NSAppleEventDescriptor(double: n)
        case let n as Int: NSAppleEventDescriptor(int32: Int32(n))
        default: NSAppleEventDescriptor.null()
        }
        list.insert(d, at: list.numberOfItems + 1)
    }
    return list
}

@Test func readsSpotifyTrackWithMillisecondDuration() throws {
    let parsed = try #require(PlayerService.parse(
        reply(["playing", "Song", "Artist", 12.5, 215000, "https://i.scdn.co/image/abc"]), app: .spotify))
    #expect(parsed.0 == TrackInfo(state: .playing, title: "Song", artist: "Artist", duration: 215,
                                  artworkKey: "https://i.scdn.co/image/abc"))
    #expect(parsed.1 == 12.5)
}

@Test func readsAppleMusicTrackWithSecondDuration() throws {
    let parsed = try #require(PlayerService.parse(
        reply(["paused", "Song", "Artist", "Album", 30.0, 215.5]), app: .music))
    #expect(parsed.0 == TrackInfo(state: .paused, title: "Song", artist: "Artist", duration: 215.5,
                                  artworkKey: "Song\nArtist\nAlbum"))
    #expect(parsed.1 == 30)
}

@Test func stoppedPlayerHasNoTrack() {
    #expect(PlayerService.parse(reply(["stopped"]), app: .spotify) == nil)
    #expect(PlayerService.parse(reply(["stopped"]), app: .music) == nil)
}
