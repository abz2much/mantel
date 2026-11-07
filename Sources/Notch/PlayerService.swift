import AppKit
import ApplicationServices
import Foundation
import os
import SwiftUI

struct TrackInfo: Equatable {
    enum PlayState { case playing, paused }
    var state: PlayState
    var title: String
    var artist: String
    var duration: TimeInterval
    /// Identifies the cover: Spotify's image URL, or title/artist/album for Apple Music.
    var artworkKey: String?
}

/// A music app Notch can show and control.
struct PlayerApp: Sendable {
    enum Kind: Sendable { case spotify, music }
    let kind: Kind
    /// Shown in the menu when control is blocked.
    let name: String
    let bundleID: String
    /// Distributed notification the app posts when playback changes.
    let notification: String

    static let spotify = PlayerApp(kind: .spotify, name: "Spotify", bundleID: "com.spotify.client",
                                   notification: "com.spotify.client.PlaybackStateChanged")
    static let music = PlayerApp(kind: .music, name: "Music", bundleID: "com.apple.Music",
                                 notification: "com.apple.Music.playerInfo")
}

/// Talks to one music app (Spotify or Apple Music) via AppleScript, off the main thread (see `AppleScriptBridge`).
/// Never launches it, and never sends an Apple event unless the app is already running.
/// Track names are never logged.
@MainActor
final class PlayerService: ObservableObject {
    private static let log = Logger(subsystem: "local.notch.app", category: "music")
    /// Seconds an Apple event to the app may take before giving up.
    nonisolated private static let eventTimeout = 3
    private static let pauseTimeout: TimeInterval = 120

    let app: PlayerApp
    /// Test-only: simulates a playing Spotify track without any Apple events.
    private let fake: Bool
    /// In fake mode the real Music app is left alone, so no Apple events are sent at all.
    private let silenced: Bool

    /// Wraps `body` in a `tell` to the app inside a timeout, so a hung app fails fast instead of waiting.
    nonisolated private static func script(_ body: String, app: PlayerApp) -> String {
        """
        with timeout of \(eventTimeout) seconds
            tell application id "\(app.bundleID)"
                \(body)
            end tell
        end timeout
        """
    }

    nonisolated private static func stateScript(_ app: PlayerApp) -> String {
        let fields = switch app.kind {
        case .spotify: "name of t, artist of t, player position, duration of t, artwork url of t"
        case .music: "name of t, artist of t, album of t, player position, duration of t"
        }
        // Apple Music also scans (fast forward / rewind); that still counts as playing. Spotify has no such states.
        let scanning = app.kind == .music ? " or player state is fast forwarding or player state is rewinding" : ""
        return script("""
            set s to "stopped"
            if player state is playing\(scanning) then
                set s to "playing"
            else if player state is paused then
                set s to "paused"
            end if
            if s is "stopped" then return {s}
            set t to current track
            return {s, \(fields)}
        """, app: app)
    }

    @Published private(set) var track: TrackInfo?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var isIdle = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var artwork: NSImage? {
        didSet { accent = artwork.flatMap(ArtworkPalette.accent(from:)).map(Color.init) }
    }
    /// Accent colour taken from the album art; nil without art or for colourless covers.
    @Published private(set) var accent: Color?

    /// Set by `MusicService` from the menu switches.
    var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { refresh() } else { clear(); setPolling(false) }
        }
    }
    var showAlbumArt = false {
        didSet { if showAlbumArt != oldValue { updateArtwork() } }
    }

    /// When playback last started and when the app was last used, for choosing between apps.
    private var activity = PlayerActivity()

    var snapshot: PlayerSnapshot {
        PlayerSnapshot(hasTrack: track != nil, isPlaying: track?.state == .playing,
                       playingSince: activity.playingSince, lastActive: activity.lastActive)
    }

    /// Track, play state, availability or idle changed.
    var onChange: (() -> Void)?
    /// Playback started or the track changed.
    var onPlay: (() -> Void)?

    private let bridge = AppleScriptBridge()
    /// Bumped when the app quits or music is turned off, so replies to earlier calls are dropped.
    private var generation = 0
    private var refreshing = false
    private var refreshAgain = false
    private var pollingPosition = false
    private var pauseTimer: Timer?
    private var positionTimer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var fakeTrack = TrackInfo(state: .playing, title: "Neon Afternoon", artist: "The Placeholders", duration: 215, artworkKey: nil)

    init(app: PlayerApp) {
        self.app = app
        let fakeMode = ProcessInfo.processInfo.environment["NOTCH_FAKE_SPOTIFY"] == "1"
        fake = app.kind == .spotify && fakeMode
        silenced = app.kind != .spotify && fakeMode
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(app.notification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let bundleID = app.bundleID
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isApp(note, bundleID) else { return }
            MainActor.assumeIsolated { self?.refresh() }
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isApp(note, bundleID) else { return }
            MainActor.assumeIsolated {
                self?.setPolling(false)
                self?.permissionDenied = false   // asked again next time it runs
                self?.clear()
            }
        }
        refresh()
    }

    nonisolated private static func isApp(_ note: Notification, _ bundleID: String) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
    }

    private var isRunning: Bool {
        if fake { return true }
        if silenced { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    // MARK: Commands

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: TimeInterval) {
        position = seconds   // show the new time straight away; the next read confirms it
        guard !fake else { return }
        command("set player position to \(Int(seconds.rounded()))", cache: false)
    }

    private func command(_ verb: String, cache: Bool = true) {
        if fake {
            switch verb {
            case "playpause": fakeTrack.state = fakeTrack.state == .playing ? .paused : .playing
            default: position = 0
            }
            update(fakeTrack)
            return
        }
        guard isRunning else { return }   // never send an Apple event (or launch the app) when it isn't running
        let gen = generation
        let source = Self.script(verb, app: app)
        Task {
            let result = await bridge.run(source, cache: cache, onlyIfRunning: app.bundleID) { _ in () }
            guard gen == generation else { return }
            if case .failure(let error) = result { record(error) }
            refresh()
        }
    }

    // MARK: State

    func refresh() {
        guard enabled, isRunning else { clear(); return }
        if fake { update(fakeTrack); updateArtwork(); return }
        // One read at a time; a request that arrives mid-read triggers one more read afterwards.
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        let gen = generation
        let app = app
        Task {
            // The first call also triggers the system Automation consent prompt.
            let result = await bridge.run(Self.stateScript(app), onlyIfRunning: app.bundleID) { Self.parse($0, app: app) }
            refreshing = false
            if gen == generation {
                switch result {
                case .success(let parsed?):
                    permissionDenied = false
                    position = parsed.1
                    update(parsed.0)
                case .success(nil):
                    permissionDenied = false
                    update(nil)
                case .failure(let error):
                    record(error)
                    update(nil)
                }
            }
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }

    /// The state script's reply as a track and the playback position; nil when stopped.
    nonisolated static func parse(_ list: NSAppleEventDescriptor, app: PlayerApp) -> (TrackInfo, Double)? {
        guard list.numberOfItems >= 6, let state = list.atIndex(1)?.stringValue else { return nil }
        let title = list.atIndex(2)?.stringValue ?? ""
        let artist = list.atIndex(3)?.stringValue ?? ""
        let playState: TrackInfo.PlayState = state == "playing" ? .playing : .paused
        switch app.kind {
        case .spotify:
            let info = TrackInfo(
                state: playState, title: title, artist: artist,
                duration: (list.atIndex(5)?.asDouble ?? 0) / 1000,   // Spotify reports milliseconds
                artworkKey: list.atIndex(6)?.stringValue
            )
            return (info, list.atIndex(4)?.asDouble ?? 0)
        case .music:
            let album = list.atIndex(4)?.stringValue ?? ""
            let info = TrackInfo(
                state: playState, title: title, artist: artist,
                duration: list.atIndex(6)?.asDouble ?? 0,   // Apple Music reports seconds
                artworkKey: [title, artist, album].joined(separator: "\n")
            )
            return (info, list.atIndex(5)?.asDouble ?? 0)
        }
    }

    private func update(_ new: TrackInfo?) {
        let old = track
        if new != old { withAnimation(.snappy) { track = new } }   // views animate song changes

        if new?.state == .paused {
            if pauseTimer == nil, !isIdle {
                pauseTimer = Timer.scheduledTimer(withTimeInterval: Self.pauseTimeout, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.pauseTimer = nil
                        self.isIdle = true
                        self.onChange?()
                    }
                }
            }
        } else {
            pauseTimer?.invalidate()
            pauseTimer = nil
            if isIdle { isIdle = false }
        }

        guard new != old else { return }
        activity = activity.updated(from: old, to: new, now: Date())
        if old?.artworkKey != new?.artworkKey { updateArtwork() }
        // Playback started or the song changed: on screens without a notch the card peeks.
        let started = new?.state == .playing && (old?.state != .playing || old?.title != new?.title || old?.artist != new?.artist)
        onChange?()
        if started { onPlay?() }
    }

    /// Forgets the current track and drops replies to any calls still in flight.
    private func clear() {
        generation += 1
        update(nil)
    }

    private func record(_ error: AppleScriptError) {
        Self.log.error("AppleScript error \(error.code) from \(self.app.name, privacy: .public)")
        if error.code == Int(errAEEventNotPermitted) {
            permissionDenied = true
            update(nil)
        }
    }

    // MARK: Position (only while the card is expanded)

    func setPolling(_ on: Bool) {
        if on, positionTimer == nil {
            positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollPosition() }
            }
            pollPosition()
        } else if !on {
            positionTimer?.invalidate()
            positionTimer = nil
        }
    }

    private func pollPosition() {
        if fake {
            if fakeTrack.state == .playing { position = min(position + 1, fakeTrack.duration) }
            return
        }
        guard isRunning else { setPolling(false); clear(); return }
        guard !pollingPosition else { return }   // skip this tick while the app is slow to answer
        pollingPosition = true
        let gen = generation
        Task {
            let result = await bridge.run(Self.script("return player position", app: app), onlyIfRunning: app.bundleID) { $0.asDouble }
            pollingPosition = false
            guard gen == generation else { return }
            switch result {
            case .success(let p?): position = p
            case .success(nil): break
            case .failure(let error): record(error)
            }
        }
    }

    // MARK: Album art (opt-in)

    /// Fake mode's cover: a generated gradient, so the glow and accents can be seen without Spotify.
    private static let fakeCover = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.2, alpha: 1),
                            NSColor(srgbRed: 0.85, green: 0.15, blue: 0.45, alpha: 1)])?.draw(in: rect, angle: -45)
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 95, dy: 95)).fill()
        return true
    }

    /// Spotify: the cover is downloaded from Spotify's image host. Apple Music: read from the app itself, no download.
    private func updateArtwork() {
        artworkTask?.cancel()
        if fake {
            withAnimation(.easeInOut(duration: 0.4)) { artwork = showAlbumArt && track != nil ? Self.fakeCover : nil }
            return
        }
        guard showAlbumArt, let key = track?.artworkKey else {
            withAnimation(.easeInOut(duration: 0.4)) { artwork = nil }
            return
        }
        switch app.kind {
        case .spotify:
            guard let url = URL(string: key), AlbumArtLoader.isAllowed(url) else {
                withAnimation(.easeInOut(duration: 0.4)) { artwork = nil }
                return
            }
            artworkTask = Task {
                let image = await AlbumArtLoader.shared.image(for: url)
                if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.4)) { artwork = image } }
            }
        case .music:
            guard isRunning else { return }
            let gen = generation
            let source = Self.script("""
                tell current track
                    if (count of artworks) is 0 then return ""
                    return raw data of artwork 1
                end tell
            """, app: app)
            artworkTask = Task {
                // Covers can be large: shrink on the bridge's queue so the main thread never decodes the full image.
                let result = await bridge.run(source, onlyIfRunning: app.bundleID) { reply -> SendableImage? in
                    guard reply.descriptorType != typeUnicodeText else { return nil }   // "" means no cover
                    return Self.thumbnail(reply.data, maxPixels: Self.coverPixels).map(SendableImage.init)
                }
                guard !Task.isCancelled, gen == generation else { return }
                let image: NSImage? = if case .success(let cover?) = result {
                    NSImage(cgImage: cover.image, size: NSSize(width: cover.image.width, height: cover.image.height))
                } else { nil }
                withAnimation(.easeInOut(duration: 0.4)) { artwork = image }
            }
        }
    }
}

extension PlayerService {
    /// Largest side of a cover after shrinking; the card shows it at 72 pt (144 px on Retina).
    nonisolated static let coverPixels = 300

    /// Decodes image data straight to a small bitmap, without decoding the full-size image first.
    nonisolated static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A finished, immutable bitmap handed from the bridge's queue to the main actor.
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

private extension NSAppleEventDescriptor {
    nonisolated var asDouble: Double? {
        guard let d = coerce(toDescriptorType: DescType(typeIEEE64BitFloatingPoint)),
              d.data.count == MemoryLayout<Double>.size else { return nil }
        return d.data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }
}
