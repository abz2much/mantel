import AppKit
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

@Test func appleMusicRadioWithMissingDetailsStillShows() throws {
    // Streams and radio can leave album and duration as "missing value".
    let parsed = try #require(PlayerService.parse(
        reply(["playing", "Live Show", "Station", NSNull(), 0.0, NSNull()]), app: .music))
    #expect(parsed.0.title == "Live Show")
    #expect(parsed.0.duration == 0)
}

@Test func largeCoverIsShrunk() throws {
    let big = NSImage(size: NSSize(width: 3000, height: 3000), flipped: false) { rect in
        NSColor.red.setFill(); rect.fill(); return true
    }
    let rep = try #require(big.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    let png = try #require(rep.representation(using: .png, properties: [:]))
    let thumb = try #require(PlayerService.thumbnail(png, maxPixels: 300))
    #expect(max(thumb.width, thumb.height) == 300)
}

@Test func coverThatIsNotAnImageGivesNothing() {
    #expect(PlayerService.thumbnail(Data([0x6D, 0x73, 0x6E, 0x67]), maxPixels: 300) == nil)
}
