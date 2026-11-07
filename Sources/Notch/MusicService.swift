import AppKit
import Combine
import SwiftUI

/// The music card's source: Spotify and Apple Music, with `PlayerChooser` deciding which one shows.
/// Views and the notch controller only talk to this; it passes commands to the chosen app.
@MainActor
final class MusicService: ObservableObject {
    private static let enabledKey = "musicCardEnabled"
    private static let artKey = "showAlbumArt"

    let players = [PlayerService(app: .spotify), PlayerService(app: .music)]
    /// The app the card shows, if any.
    @Published private(set) var current: PlayerService?

    @Published var musicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: Self.enabledKey)
            players.forEach { $0.enabled = musicEnabled }
        }
    }
    @Published var showAlbumArt: Bool {
        didSet {
            UserDefaults.standard.set(showAlbumArt, forKey: Self.artKey)
            players.forEach { $0.showAlbumArt = showAlbumArt }
        }
    }

    /// Track, play state, availability or idle changed.
    var onChange: (() -> Void)?
    /// Playback started or the track changed in the app the card shows.
    var onPlay: (() -> Void)?

    private var forwarding: [AnyCancellable] = []
    private var polling = false

    init() {
        let defaults = UserDefaults.standard
        musicEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        showAlbumArt = defaults.object(forKey: Self.artKey) as? Bool ?? false
        for player in players {
            player.enabled = musicEnabled
            player.showAlbumArt = showAlbumArt
            player.onChange = { [weak self] in
                self?.choose()
                self?.onChange?()
            }
            player.onPlay = { [weak self, weak player] in
                guard let self else { return }
                choose()
                if current === player { onPlay?() }
            }
            // Views watch this object, so pass on every change in either app (track, position, art, permission).
            forwarding.append(player.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        }
    }

    func start() { players.forEach { $0.start() } }
    func refresh() { players.forEach { $0.refresh() } }

    private func choose() {
        let chosen = PlayerChooser.pick(players.map(\.snapshot)).map { players[$0] }
        guard chosen !== current else { return }
        withAnimation(.snappy) { current = chosen }   // switching apps animates like a song change
        applyPolling()
    }

    // MARK: What the card shows

    var track: TrackInfo? { current?.track }
    var position: TimeInterval { current?.position ?? 0 }
    var artwork: NSImage? { current?.artwork }
    var accent: Color? { current?.accent }
    var isIdle: Bool { current?.isIdle ?? false }
    var showsCard: Bool { musicEnabled && current != nil && !isIdle && track != nil }
    /// Names of apps whose Automation permission was refused, for the menu.
    var blockedApps: [String] { players.filter(\.permissionDenied).map(\.app.name) }

    // MARK: Commands

    func playPause() { current?.playPause() }
    func next() { current?.next() }
    func previous() { current?.previous() }
    func seek(to seconds: TimeInterval) { current?.seek(to: seconds) }

    /// Position polling, only for the app on show and only while the card is expanded.
    func setPolling(_ on: Bool) {
        polling = on
        applyPolling()
    }

    private func applyPolling() {
        for player in players { player.setPolling(polling && player === current) }
    }
}
