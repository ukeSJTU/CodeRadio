import AppKit
import AVFoundation
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
    private static let qualityKey = "CodeRadio.quality"

    var isPlaying = false
    var isRefreshing = false
    var isOnline = true
    var listenerCount = 0
    var currentSong: Song?
    var songHistory: [Song] = []
    var playedAt: Date?
    var songDuration: TimeInterval = 0
    var errorMessage: String?

    var volume: Double {
        didSet {
            let clampedVolume = min(max(volume, 0), 1)
            if volume != clampedVolume {
                volume = clampedVolume
                return
            }
            player.volume = Float(clampedVolume)
            UserDefaults.standard.set(clampedVolume, forKey: Self.volumeKey)
        }
    }

    var selectedQuality: StreamQuality {
        didSet {
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: Self.qualityKey)
            if isPlaying {
                play()
            }
        }
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var mounts: [StreamMount] = []
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var playbackFailureObserver: NSObjectProtocol?
    @ObservationIgnored private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodeRadio",
        category: "player"
    )

    init() {
        let savedVolume = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double
        volume = savedVolume ?? 0.5

        let savedQuality = UserDefaults.standard.string(forKey: Self.qualityKey)
        selectedQuality = StreamQuality(rawValue: savedQuality ?? "") ?? .high

        player.volume = Float(volume)
        configurePlaybackFailureHandling()
        configureRemoteCommands()
        startMetadataUpdates()
    }

    var progress: Double {
        guard let playedAt, songDuration > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(playedAt) / songDuration, 0), 1)
    }

    var selectedStreamLabel: String {
        selectedQuality.label
    }

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        errorMessage = nil
        let item = AVPlayerItem(url: streamURL(for: selectedQuality))
        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.play()
        isPlaying = true
        updateSystemNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func openWebsite() {
        NSWorkspace.shared.open(Self.websiteURL)
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
            mounts = payload.station.mounts
            isOnline = payload.isOnline
            listenerCount = payload.listeners.current
            currentSong = payload.nowPlaying.song
            playedAt = Date(timeIntervalSince1970: payload.nowPlaying.playedAt)
            songDuration = payload.nowPlaying.duration
            songHistory = payload.songHistory.map(\.song)
            errorMessage = nil
            updateSystemNowPlaying()
        } catch {
            logger.error("Metadata refresh failed: \(error.localizedDescription, privacy: .public)")
            if currentSong == nil {
                errorMessage = "Unable to load station information"
            }
        }
    }

    private func startMetadataUpdates() {
        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMetadata()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func streamURL(for quality: StreamQuality) -> URL {
        let sortedMounts = mounts.sorted { $0.bitrate < $1.bitrate }
        switch quality {
        case .high:
            return sortedMounts.last?.url ?? quality.fallbackURL
        case .low:
            return sortedMounts.first?.url ?? quality.fallbackURL
        }
    }

    private func configurePlaybackFailureHandling() {
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let underlyingError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
                as? Error
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure(underlyingError)
            }
        }
    }

    private func handlePlaybackFailure(_ error: Error?) {
        logger.error("Playback failed: \(error?.localizedDescription ?? "Unknown error", privacy: .public)")
        if selectedQuality == .high {
            selectedQuality = .low
            errorMessage = "128 kbps stream unavailable; switched to 64 kbps"
        } else {
            stop()
            errorMessage = "The Code Radio stream is currently unavailable"
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
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
    }

    private func updateSystemNowPlaying() {
        guard let currentSong else {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPMediaItemPropertyArtist: currentSong.artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if !currentSong.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = currentSong.album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .stopped
    }
}
