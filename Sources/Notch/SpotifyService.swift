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
    var artworkURL: URL?
}

/// Talks to the Spotify desktop app via AppleScript, off the main thread (see `AppleScriptBridge`).
/// Never launches it, and never sends an Apple event unless Spotify is already running.
/// Track names are never logged.
@MainActor
final class SpotifyService: ObservableObject {
    private static let log = Logger(subsystem: "local.notch.app", category: "music")
    nonisolated private static let bundleID = "com.spotify.client"
    /// Seconds an Apple event to Spotify may take before giving up.
    nonisolated private static let eventTimeout = 3
    private static let pauseTimeout: TimeInterval = 120
    private static let enabledKey = "musicCardEnabled"
    private static let artKey = "showAlbumArt"
    /// Test-only: simulates a playing track without any Apple events.
    private static let fake = ProcessInfo.processInfo.environment["NOTCH_FAKE_SPOTIFY"] == "1"

    /// Wraps `body` in a `tell` to Spotify inside a timeout, so a hung Spotify fails fast instead of waiting.
    nonisolated private static func script(_ body: String) -> String {
        """
        with timeout of \(eventTimeout) seconds
            tell application id "\(bundleID)"
                \(body)
            end tell
        end timeout
        """
    }

    nonisolated private static let stateScript = script("""
        set s to "stopped"
        if player state is playing then
            set s to "playing"
        else if player state is paused then
            set s to "paused"
        end if
        if s is "stopped" then return {s}
        set t to current track
        return {s, name of t, artist of t, player position, duration of t, artwork url of t}
    """)
    nonisolated private static let positionScript = script("return player position")

    @Published private(set) var track: TrackInfo?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var isIdle = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var artwork: NSImage? {
        didSet { accent = artwork.flatMap(ArtworkPalette.accent(from:)).map(Color.init) }
    }
    /// Accent colour taken from the album art; nil without art or for colourless covers.
    @Published private(set) var accent: Color?

    @Published var musicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: Self.enabledKey)
            if musicEnabled { refresh() } else { clear(); setPolling(false) }
        }
    }
    @Published var showAlbumArt: Bool {
        didSet {
            UserDefaults.standard.set(showAlbumArt, forKey: Self.artKey)
            updateArtwork()
        }
    }

    /// Track, play state, availability or idle changed.
    var onChange: (() -> Void)?
    /// Playback started or the track changed.
    var onPlay: (() -> Void)?

    var showsCard: Bool { musicEnabled && !permissionDenied && !isIdle && track != nil }

    private let bridge = AppleScriptBridge()
    /// Bumped when Spotify quits or music is turned off, so replies to earlier calls are dropped.
    private var generation = 0
    private var refreshing = false
    private var refreshAgain = false
    private var pollingPosition = false
    private var pauseTimer: Timer?
    private var positionTimer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var fakeTrack = TrackInfo(state: .playing, title: "Test Track", artist: "Test Artist", duration: 215, artworkURL: nil)

    init() {
        let defaults = UserDefaults.standard
        musicEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        showAlbumArt = defaults.object(forKey: Self.artKey) as? Bool ?? false
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.log.info("PlaybackStateChanged received")
                self?.refresh()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            MainActor.assumeIsolated { self?.refresh() }
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            MainActor.assumeIsolated {
                self?.setPolling(false)
                self?.clear()
            }
        }
        refresh()
    }

    nonisolated private static func isSpotify(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
    }

    private var isRunning: Bool {
        Self.fake || !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: Commands

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: TimeInterval) {
        position = seconds   // show the new time straight away; the next read confirms it
        guard !Self.fake else { return }
        command("set player position to \(Int(seconds.rounded()))", cache: false)
    }

    private func command(_ verb: String, cache: Bool = true) {
        if Self.fake {
            switch verb {
            case "playpause": fakeTrack.state = fakeTrack.state == .playing ? .paused : .playing
            default: position = 0
            }
            update(fakeTrack)
            return
        }
        guard isRunning else { return }   // never send an Apple event (or launch Spotify) when it isn't running
        let gen = generation
        Task {
            let result = await bridge.run(Self.script(verb), cache: cache) { _ in () }
            guard gen == generation else { return }
            if case .failure(let error) = result { record(error) }
            refresh()
        }
    }

    // MARK: State

    func refresh() {
        guard musicEnabled, isRunning else { clear(); return }
        if Self.fake { update(fakeTrack); return }
        // One read at a time; a request that arrives mid-read triggers one more read afterwards.
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        let gen = generation
        Task {
            // The first call also triggers the system Automation consent prompt.
            let result = await bridge.run(Self.stateScript) { Self.parse($0) }
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

    nonisolated private static func parse(_ list: NSAppleEventDescriptor) -> (TrackInfo, Double)? {
        guard list.numberOfItems >= 6, let state = list.atIndex(1)?.stringValue else { return nil }
        let info = TrackInfo(
            state: state == "playing" ? .playing : .paused,
            title: list.atIndex(2)?.stringValue ?? "",
            artist: list.atIndex(3)?.stringValue ?? "",
            duration: (list.atIndex(5)?.asDouble ?? 0) / 1000,   // Spotify reports milliseconds
            artworkURL: list.atIndex(6)?.stringValue.flatMap(URL.init(string:))
        )
        return (info, list.atIndex(4)?.asDouble ?? 0)
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
        if old?.artworkURL != new?.artworkURL { updateArtwork() }
        if new?.state == .playing, old?.state != .playing || old?.title != new?.title || old?.artist != new?.artist {
            onPlay?()
        }
        onChange?()
    }

    /// Forgets the current track and drops replies to any calls still in flight.
    private func clear() {
        generation += 1
        update(nil)
    }

    private func record(_ error: AppleScriptError) {
        Self.log.error("AppleScript error \(error.code)")
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
        if Self.fake {
            if fakeTrack.state == .playing { position = min(position + 1, fakeTrack.duration) }
            return
        }
        guard isRunning else { setPolling(false); clear(); return }
        guard !pollingPosition else { return }   // skip this tick while Spotify is slow to answer
        pollingPosition = true
        let gen = generation
        Task {
            let result = await bridge.run(Self.positionScript) { $0.asDouble }
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

    private func updateArtwork() {
        artworkTask?.cancel()
        guard showAlbumArt, let url = track?.artworkURL, AlbumArtLoader.isAllowed(url) else {
            withAnimation(.easeInOut(duration: 0.4)) { artwork = nil }
            return
        }
        artworkTask = Task {
            let image = await AlbumArtLoader.shared.image(for: url)
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.4)) { artwork = image } }
        }
    }
}

private extension NSAppleEventDescriptor {
    nonisolated var asDouble: Double? {
        guard let d = coerce(toDescriptorType: DescType(typeIEEE64BitFloatingPoint)),
              d.data.count == MemoryLayout<Double>.size else { return nil }
        return d.data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }
}
