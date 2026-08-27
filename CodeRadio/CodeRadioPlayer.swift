import AppKit
import MediaPlayer
import Observation
import OSLog

@MainActor
@Observable
final class CodeRadioPlayer {
    private static let metadataURL = URL(
        string: "https://coderadio-admin-v2.freecodecamp.org/api/nowplaying_static/coderadio.json"
    )!

    private static let websiteURL = URL(string: "https://coderadio.freecodecamp.org/")!
    private static let volumeKey = "CodeRadio.volume"

    var isRefreshing = false
    var stationIsOnline = true
    var listenerCount = 0
    var currentSong: Song?
    var songHistory: [Song] = []
    var playedAt: Date?
    var songDuration: TimeInterval = 0
    var metadataErrorMessage: String?

    var volume: Double {
        didSet {
            let clampedVolume = min(max(volume, 0), 1)
            if volume != clampedVolume {
                volume = clampedVolume
                return
            }
            playback.setVolume(Float(clampedVolume))
            UserDefaults.standard.set(clampedVolume, forKey: Self.volumeKey)
        }
    }

    var selectedQuality: StreamQuality {
        get { playback.snapshot.preferredQuality }
        set { playback.setPreferredQuality(newValue) }
    }

    var playbackPresentation: PlaybackPresentation {
        PlaybackPresentation(snapshot: playback.snapshot)
    }

    @ObservationIgnored private let playback: PlaybackCoordinator
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var announceRecoveryAfterRetry = false
    @ObservationIgnored private var fallbackAnnouncementPending = false
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodeRadio",
        category: "player"
    )

    convenience init() {
        let coordinator = PlaybackCoordinator(
            engine: AVPlayerPlaybackEngine(),
            scheduler: TaskPlaybackDeadlineScheduler(),
            connectivity: NWPathConnectivitySource(),
            sleepWake: WorkspaceSleepWakeSource(),
            preferences: UserDefaultsPlaybackPreferences()
        )
        self.init(playback: coordinator)
    }

    init(playback: PlaybackCoordinator) {
        self.playback = playback
        let savedVolume = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double
        volume = savedVolume ?? 0.5

        playback.setVolume(Float(volume))
        playback.snapshotDidChange = { [weak self] oldSnapshot, newSnapshot in
            self?.playbackDidChange(from: oldSnapshot, to: newSnapshot)
        }
        configureRemoteCommands()
        updateSystemNowPlaying()
        startMetadataUpdates()
    }

    var progress: Double {
        guard let playedAt, songDuration > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(playedAt) / songDuration, 0), 1)
    }

    func play() {
        playback.play()
    }

    func stop() {
        announceRecoveryAfterRetry = false
        fallbackAnnouncementPending = false
        playback.stop()
    }

    func retry() {
        announceRecoveryAfterRetry = true
        playback.retry()
    }

    func togglePlayback() {
        switch playback.snapshot.phase {
        case .stopped:
            play()
        case .failed:
            retry()
        case .connecting, .playing, .reconnecting, .offline:
            stop()
        }
    }

    func openWebsite() {
        NSWorkspace.shared.open(Self.websiteURL)
    }

    func quit() {
        metadataTask?.cancel()
        metadataTask = nil
        playback.shutdown()
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        remoteCommandTargets.removeAll()
        NSApplication.shared.terminate(nil)
    }

    func refreshMetadata() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: Self.metadataURL)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw URLError(.badServerResponse)
            }

            let payload = try JSONDecoder.codeRadio.decode(CodeRadioResponse.self, from: data)
            playback.updateMounts(payload.station.mounts)
            stationIsOnline = payload.isOnline
            listenerCount = payload.listeners.current
            currentSong = payload.nowPlaying.song
            playedAt = Date(timeIntervalSince1970: payload.nowPlaying.playedAt)
            songDuration = payload.nowPlaying.duration
            songHistory = payload.songHistory.map(\.song)
            metadataErrorMessage = nil
            updateSystemNowPlaying()
        } catch {
            logger.error("Metadata refresh failed: \(error.localizedDescription, privacy: .public)")
            if currentSong == nil {
                metadataErrorMessage = String(localized: "Unable to load station information")
            }
        }
    }

    private func startMetadataUpdates() {
        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMetadata()
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
            }
        }
    }

    private func playbackDidChange(
        from oldSnapshot: PlaybackSnapshot,
        to newSnapshot: PlaybackSnapshot
    ) {
        logger.debug(
            "Playback state changed to \(String(describing: newSnapshot.phase), privacy: .public)"
        )
        updateRemoteCommandAvailability()
        updateSystemNowPlaying()

        if !oldSnapshot.isUsingTemporaryFallback && newSnapshot.isUsingTemporaryFallback {
            fallbackAnnouncementPending = true
        } else if !newSnapshot.isUsingTemporaryFallback {
            fallbackAnnouncementPending = false
        }

        if oldSnapshot.phase != newSnapshot.phase {
            switch newSnapshot.phase {
            case .offline:
                postAccessibilityAnnouncement(
                    String(localized: "No network connection. Playback will resume automatically.")
                )
            case .failed(let reason):
                let message = PlaybackPresentation(snapshot: newSnapshot)
                    .statusMessages
                    .first { $0.showsRetry }?
                    .message
                    ?? String(localized: "Playback failed.")
                logger.error(
                    "Playback recovery exhausted: \(String(describing: reason), privacy: .public)"
                )
                postAccessibilityAnnouncement(message)
            case .playing:
                if fallbackAnnouncementPending {
                    fallbackAnnouncementPending = false
                    postAccessibilityAnnouncement(
                        String(localized: "Playing at 64 kbps. Your 128 kbps preference is unchanged.")
                    )
                }
                if announceRecoveryAfterRetry {
                    announceRecoveryAfterRetry = false
                    postAccessibilityAnnouncement(String(localized: "Playback restored."))
                }
            case .stopped, .connecting, .reconnecting:
                break
            }
        }
    }

    private func postAccessibilityAnnouncement(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed = self.playback.snapshot.phase {
                    self.retry()
                } else {
                    self.play()
                }
            }
            return .success
        }
        remoteCommandTargets.append((commandCenter.playCommand, playTarget))

        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
            return .success
        }
        remoteCommandTargets.append((commandCenter.pauseCommand, pauseTarget))

        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayback() }
            return .success
        }
        remoteCommandTargets.append((commandCenter.togglePlayPauseCommand, toggleTarget))
        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        switch playback.snapshot.phase {
        case .stopped, .failed:
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = playback.snapshot.intent == .playing
        case .connecting, .playing, .reconnecting, .offline:
            commandCenter.playCommand.isEnabled = false
            commandCenter.pauseCommand.isEnabled = true
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
    }

    private func updateSystemNowPlaying() {
        let presentation = playbackPresentation
        let playbackState: MPNowPlayingPlaybackState
        switch presentation.systemState {
        case .playing:
            playbackState = .playing
        case .interrupted:
            playbackState = .interrupted
        case .stopped:
            playbackState = .stopped
        }

        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = playbackState

        guard let currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPMediaItemPropertyArtist: currentSong.artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: presentation.playbackRate,
        ]
        if !currentSong.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = currentSong.album
        }
        center.nowPlayingInfo = info
    }

    deinit {
        metadataTask?.cancel()
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
    }
}
