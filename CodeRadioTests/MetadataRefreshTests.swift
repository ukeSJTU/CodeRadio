import Foundation
import Testing
@testable import CodeRadio

@Suite("Station metadata refresh")
@MainActor
struct MetadataRefreshTests {
    @Test("A complete refresh publishes fresh station metadata")
    func completeRefreshPublishesFreshMetadata() async throws {
        let response = try decodeMetadata(
            """
            {
              "station": {
                "mounts": [
                  {
                    "id": 1,
                    "name": "128kbps MP3",
                    "url": "https://example.com/radio.mp3",
                    "bitrate": 128
                  }
                ]
              },
              "listeners": { "current": 42 },
              "now_playing": {
                "played_at": 1000,
                "duration": 180,
                "song": {
                  "id": "song-1",
                  "title": "Test Track",
                  "artist": "Test Artist",
                  "album": "Test Album",
                  "art": "https://example.com/art.jpg"
                }
              },
              "song_history": [
                {
                  "played_at": 900,
                  "song": {
                    "id": "song-0",
                    "title": "Previous Track",
                    "artist": "Previous Artist",
                    "album": "Previous Album"
                  }
                }
              ],
              "is_online": true
            }
            """
        )
        let player = makePlayer(metadataResult: .success(response))

        await player.refreshMetadata()

        #expect(player.currentSong?.title == "Test Track")
        #expect(player.songHistory.map(\.title) == ["Previous Track"])
        #expect(player.listenerCount == 42)
        #expect(player.stationIsOnline == true)
        #expect(player.hasSongProgress)
        #expect(!player.metadataIsStale)
        #expect(player.metadataErrorMessage == nil)
    }

    @Test("A failed refresh retains the current song and marks it stale")
    func failedRefreshRetainsStaleSong() async throws {
        let response = try decodeMetadata(
            """
            {
              "station": {
                "mounts": [
                  {
                    "id": 1,
                    "name": "128kbps MP3",
                    "url": "https://example.com/live-high.mp3",
                    "bitrate": 128
                  }
                ]
              },
              "listeners": { "current": 7 },
              "now_playing": {
                "played_at": 1000,
                "duration": 180,
                "song": {
                  "id": "song-1",
                  "title": "Last Known Track",
                  "artist": "Test Artist",
                  "album": ""
                }
              },
              "song_history": [
                {
                  "played_at": 900,
                  "song": {
                    "id": "song-0",
                    "title": "Previous Track",
                    "artist": "Previous Artist",
                    "album": ""
                  }
                }
              ],
              "is_online": true
            }
            """
        )
        let results = MetadataResultQueue([
            .success(response),
            .failure(URLError(.timedOut)),
        ])
        let playbackSystem = MetadataTestPlaybackFactory.makeSystem()
        let player = CodeRadioPlayer(
            playback: playbackSystem.coordinator,
            metadataClient: StationMetadataClient(load: { try results.next() }),
            startsMetadataUpdates: false
        )

        await player.refreshMetadata()
        await player.refreshMetadata()

        #expect(player.currentSong?.title == "Last Known Track")
        #expect(player.metadataIsStale)
        #expect(player.metadataErrorMessage == "Station information may be out of date")
        #expect(player.songHistory.isEmpty)
        #expect(player.listenerCount == nil)
        #expect(player.stationIsOnline == nil)
        #expect(!player.hasSongProgress)
        #expect(playbackSystem.coordinator.snapshot.phase == .stopped)

        player.play()

        #expect(playbackSystem.engine.loads == [StreamQuality.high.fallbackURL])
    }

    @Test("Cancelling metadata work does not publish a failure")
    func cancelledRefreshDoesNotPublishFailure() async {
        let player = makePlayer(metadataResult: .failure(CancellationError()))

        await player.refreshMetadata()

        #expect(player.metadataErrorMessage == nil)
        #expect(!player.metadataIsStale)
        #expect(!player.isRefreshing)
    }

    @Test("A first-load failure exposes only the station information error")
    func firstLoadFailureUsesDefaultMetadataState() async {
        let player = makePlayer(metadataResult: .failure(URLError(.badServerResponse)))

        await player.refreshMetadata()

        #expect(player.currentSong == nil)
        #expect(player.metadataErrorMessage == "Unable to load station information")
        #expect(!player.metadataIsStale)
        #expect(player.listenerCount == nil)
        #expect(player.stationIsOnline == nil)
        #expect(player.songHistory.isEmpty)
        #expect(!player.hasSongProgress)
        #expect(player.playbackPresentation.statusMessages.isEmpty)
    }

    @Test("A partial refresh publishes only the metadata it actually contains")
    func partialRefreshDegradesIndependently() async throws {
        let response = try decodeMetadata(
            """
            {
              "listeners": { "current": 0 },
              "now_playing": {
                "song": {
                  "id": "song-2",
                  "title": "Untimed Track",
                  "artist": "Test Artist"
                }
              }
            }
            """
        )
        let playbackSystem = MetadataTestPlaybackFactory.makeSystem()
        let player = CodeRadioPlayer(
            playback: playbackSystem.coordinator,
            metadataClient: StationMetadataClient(load: { response }),
            startsMetadataUpdates: false
        )

        await player.refreshMetadata()

        #expect(player.currentSong?.title == "Untimed Track")
        #expect(player.listenerCount == 0)
        #expect(player.stationStatusText == "Live · 0")
        #expect(player.stationIsOnline == nil)
        #expect(player.songHistory.isEmpty)
        #expect(!player.hasSongProgress)
        #expect(!player.metadataIsStale)
        #expect(player.metadataErrorMessage == nil)

        player.play()

        #expect(playbackSystem.engine.loads == [StreamQuality.high.fallbackURL])
        #expect(playbackSystem.coordinator.snapshot.preferredQuality == .high)
        #expect(playbackSystem.preferences.preferredQuality == .high)
    }

    @Test("A missing listener count never appears as zero")
    func missingListenerCountUsesUnnumberedLiveStatus() async throws {
        let response = try decodeMetadata(
            """
            {
              "now_playing": {
                "song": {
                  "id": "song-no-listeners",
                  "title": "Listenerless Metadata",
                  "artist": "Test Artist"
                }
              },
              "is_online": true
            }
            """
        )
        let player = makePlayer(metadataResult: .success(response))

        await player.refreshMetadata()

        #expect(player.listenerCount == nil)
        #expect(player.stationStatusText == "Live")
        #expect(!player.stationStatusText.contains("0"))
    }

    @Test("A partial response without a first song uses unavailable metadata state")
    func missingFirstSongUsesUnavailableState() async throws {
        let response = try decodeMetadata(#"{ "listeners": { "current": 5 } }"#)
        let player = makePlayer(metadataResult: .success(response))

        await player.refreshMetadata()

        #expect(player.currentSong == nil)
        #expect(player.listenerCount == 5)
        #expect(player.metadataState == .unavailable)
        #expect(player.metadataErrorMessage == "Unable to load station information")
        #expect(!player.metadataIsStale)
    }

    @Test("Automatic and manual refresh apply the same metadata state")
    func automaticAndManualRefreshAreEquivalent() async throws {
        let response = try decodeMetadata(
            """
            {
              "listeners": { "current": 12 },
              "now_playing": {
                "song": {
                  "id": "song-auto",
                  "title": "Shared Refresh Track",
                  "artist": "Shared Artist"
                }
              }
            }
            """
        )
        let manualPlayer = makePlayer(metadataResult: .success(response))
        await manualPlayer.refreshMetadata()

        await confirmation("Automatic refresh loads metadata") { refreshStarted in
            let automaticPlayer = CodeRadioPlayer(
                playback: MetadataTestPlaybackFactory.makeCoordinator(),
                metadataClient: StationMetadataClient(load: {
                    refreshStarted()
                    return response
                }),
                startsMetadataUpdates: true
            )

            for _ in 0..<100 where automaticPlayer.metadataState == .idle {
                await Task.yield()
            }

            #expect(automaticPlayer.currentSong == manualPlayer.currentSong)
            #expect(automaticPlayer.listenerCount == manualPlayer.listenerCount)
            #expect(automaticPlayer.stationIsOnline == manualPlayer.stationIsOnline)
            #expect(automaticPlayer.songHistory == manualPlayer.songHistory)
            #expect(automaticPlayer.metadataState == manualPlayer.metadataState)
            #expect(automaticPlayer.hasSongProgress == manualPlayer.hasSongProgress)
        }
    }

    @Test("Fresh song metadata clears a stale partial response")
    func freshSongClearsStalePartialResponse() async throws {
        let first = try decodeMetadata(
            """
            {
              "now_playing": {
                "played_at": 1000,
                "duration": 180,
                "song": {
                  "id": "song-1",
                  "title": "First Track",
                  "artist": "First Artist"
                }
              }
            }
            """
        )
        let missingSong = try decodeMetadata(#"{ "listeners": { "current": 5 } }"#)
        let recovered = try decodeMetadata(
            """
            {
              "now_playing": {
                "played_at": 2000,
                "duration": 240,
                "song": {
                  "id": "song-2",
                  "title": "Recovered Track",
                  "artist": "Recovered Artist"
                }
              }
            }
            """
        )
        let results = MetadataResultQueue([
            .success(first),
            .success(missingSong),
            .success(recovered),
        ])
        let player = makePlayer(
            metadataClient: StationMetadataClient(load: { try results.next() })
        )

        await player.refreshMetadata()
        await player.refreshMetadata()

        #expect(player.currentSong?.title == "First Track")
        #expect(player.metadataIsStale)
        #expect(!player.hasSongProgress)
        #expect(player.metadataErrorMessage == "Station information may be out of date")

        await player.refreshMetadata()

        #expect(player.currentSong?.title == "Recovered Track")
        #expect(!player.metadataIsStale)
        #expect(player.hasSongProgress)
        #expect(player.metadataErrorMessage == nil)
    }

    @Test("Metadata failures never mutate observed playback state")
    func metadataFailurePreservesPlaybackState() async {
        let playbackSystem = MetadataTestPlaybackFactory.makeSystem()
        let player = CodeRadioPlayer(
            playback: playbackSystem.coordinator,
            metadataClient: StationMetadataClient(
                load: { throw URLError(.cannotConnectToHost) }
            ),
            startsMetadataUpdates: false
        )

        player.play()
        playbackSystem.engine.emit(.playing)
        #expect(playbackSystem.coordinator.snapshot.phase == .playing)

        await player.refreshMetadata()
        #expect(playbackSystem.coordinator.snapshot.phase == .playing)

        playbackSystem.engine.emit(.waiting)
        #expect(playbackSystem.coordinator.snapshot.phase == .reconnecting)

        await player.refreshMetadata()
        #expect(playbackSystem.coordinator.snapshot.phase == .reconnecting)

        player.stop()
        await player.refreshMetadata()
        #expect(playbackSystem.coordinator.snapshot.phase == .stopped)
    }

    private func decodeMetadata(_ json: String) throws -> CodeRadioResponse {
        try JSONDecoder.codeRadio.decode(
            CodeRadioResponse.self,
            from: Data(json.utf8)
        )
    }

    private func makePlayer(
        metadataResult: Result<CodeRadioResponse, any Error>
    ) -> CodeRadioPlayer {
        makePlayer(
            metadataClient: StationMetadataClient(
                load: { try metadataResult.get() }
            )
        )
    }

    private func makePlayer(metadataClient: StationMetadataClient) -> CodeRadioPlayer {
        CodeRadioPlayer(
            playback: MetadataTestPlaybackFactory.makeCoordinator(),
            metadataClient: metadataClient,
            startsMetadataUpdates: false
        )
    }
}

@MainActor
private final class MetadataResultQueue {
    private var results: [Result<CodeRadioResponse, any Error>]

    init(_ results: [Result<CodeRadioResponse, any Error>]) {
        self.results = results
    }

    func next() throws -> CodeRadioResponse {
        guard !results.isEmpty else { throw URLError(.unknown) }
        return try results.removeFirst().get()
    }
}

@MainActor
private enum MetadataTestPlaybackFactory {
    static func makeCoordinator() -> PlaybackCoordinator {
        makeSystem().coordinator
    }

    static func makeSystem() -> MetadataTestPlaybackSystem {
        let engine = IdlePlaybackEngine()
        let preferences = MemoryPlaybackPreferences()
        let coordinator = PlaybackCoordinator(
            engine: engine,
            scheduler: IdlePlaybackScheduler(),
            connectivity: IdleConnectivitySource(),
            sleepWake: IdleSleepWakeSource(),
            preferences: preferences
        )
        return MetadataTestPlaybackSystem(
            coordinator: coordinator,
            engine: engine,
            preferences: preferences
        )
    }
}

@MainActor
private struct MetadataTestPlaybackSystem {
    let coordinator: PlaybackCoordinator
    let engine: IdlePlaybackEngine
    let preferences: MemoryPlaybackPreferences
}

@MainActor
private final class IdlePlaybackEngine: PlaybackEngine {
    var eventHandler: ((PlaybackAttemptID, PlaybackEngineEvent) -> Void)?
    var volume: Float = 0
    private(set) var loads: [URL] = []

    func load(url: URL, attemptID: PlaybackAttemptID) {
        loads.append(url)
    }

    func emit(_ event: PlaybackEngineEvent, attemptID: PlaybackAttemptID = .init(rawValue: 1)) {
        eventHandler?(attemptID, event)
    }

    func stop() {}
}

@MainActor
private final class IdlePlaybackScheduler: PlaybackDeadlineScheduling {
    func schedule(
        _ deadline: PlaybackDeadline,
        handler: @escaping (PlaybackDeadlineID) -> Void
    ) {}

    func cancel() {}
}

@MainActor
private final class IdleConnectivitySource: PlaybackConnectivitySourcing {
    var handler: ((PlaybackConnectivity) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class IdleSleepWakeSource: PlaybackSleepWakeSourcing {
    var sleepHandler: (() -> Void)?
    var wakeHandler: (() -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class MemoryPlaybackPreferences: PlaybackPreferenceStoring {
    var preferredQuality: StreamQuality = .high
}
