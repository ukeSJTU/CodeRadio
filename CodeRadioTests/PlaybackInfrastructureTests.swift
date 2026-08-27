import Foundation
import Testing
@testable import CodeRadio

@Suite("Playback infrastructure")
@MainActor
struct PlaybackInfrastructureTests {
    @Test("Each connection resolves the newest mount for its effective quality")
    func streamURLResolution() {
        let lowURL = URL(string: "https://example.com/low.mp3")!
        let highURL = URL(string: "https://example.com/high.mp3")!
        let mounts = [
            StreamMount(id: 1, name: "Low", url: lowURL, bitrate: 64),
            StreamMount(id: 2, name: "High", url: highURL, bitrate: 128),
        ]
        let resolver = StreamURLResolver()

        #expect(resolver.url(for: .low, mounts: mounts) == lowURL)
        #expect(resolver.url(for: .high, mounts: mounts) == highURL)
        #expect(resolver.url(for: .low, mounts: []) == StreamQuality.low.fallbackURL)
        #expect(resolver.url(for: .high, mounts: []) == StreamQuality.high.fallbackURL)
    }

    @Test("Coordinator executes machine effects through injected boundaries")
    func coordinatorExecutesPlaybackEffects() {
        let engine = FakePlaybackEngine()
        let scheduler = FakePlaybackScheduler()
        let connectivity = FakeConnectivitySource()
        let sleepWake = FakeSleepWakeSource()
        let preferences = FakePlaybackPreferences(preferredQuality: .high)
        let coordinator = PlaybackCoordinator(
            engine: engine,
            scheduler: scheduler,
            connectivity: connectivity,
            sleepWake: sleepWake,
            preferences: preferences
        )

        coordinator.play()

        #expect(coordinator.snapshot.phase == .connecting(.connecting))
        #expect(engine.loads.count == 1)
        #expect(engine.loads.first?.url == StreamQuality.high.fallbackURL)
        #expect(engine.loads.first?.attemptID.rawValue == 1)
        #expect(scheduler.scheduled?.kind == .startup(attemptID: .init(rawValue: 1)))

        engine.emit(.waiting, attemptID: .init(rawValue: 1))
        #expect(coordinator.snapshot.phase == .connecting(.buffering))

        coordinator.stop()
        #expect(coordinator.snapshot.phase == .stopped)
        #expect(engine.stopCount == 1)
        #expect(scheduler.cancelCount == 1)
    }

    @Test("Temporary fallback never overwrites the saved preference")
    func temporaryFallbackDoesNotPersist() {
        let engine = FakePlaybackEngine()
        let scheduler = FakePlaybackScheduler()
        let preferences = FakePlaybackPreferences(preferredQuality: .high)
        let coordinator = PlaybackCoordinator(
            engine: engine,
            scheduler: scheduler,
            connectivity: FakeConnectivitySource(),
            sleepWake: FakeSleepWakeSource(),
            preferences: preferences
        )
        coordinator.play()

        engine.emit(.failed(.transient), attemptID: .init(rawValue: 1))
        scheduler.fire()
        engine.emit(.failed(.transient), attemptID: .init(rawValue: 2))
        scheduler.fire()

        #expect(coordinator.snapshot.effectiveQuality == .low)
        #expect(coordinator.snapshot.preferredQuality == .high)
        #expect(preferences.preferredQuality == .high)
        #expect(preferences.writeCount == 0)
    }

    @Test("Coordinator shutdown cancels every long-running boundary exactly once")
    func coordinatorShutdownIsIdempotent() {
        let engine = FakePlaybackEngine()
        let scheduler = FakePlaybackScheduler()
        let connectivity = FakeConnectivitySource()
        let sleepWake = FakeSleepWakeSource()
        let coordinator = PlaybackCoordinator(
            engine: engine,
            scheduler: scheduler,
            connectivity: connectivity,
            sleepWake: sleepWake,
            preferences: FakePlaybackPreferences(preferredQuality: .high)
        )
        coordinator.play()

        coordinator.shutdown()
        coordinator.shutdown()
        coordinator.play()

        #expect(scheduler.cancelCount == 1)
        #expect(engine.stopCount == 1)
        #expect(connectivity.stopCount == 1)
        #expect(sleepWake.stopCount == 1)
        #expect(engine.loads.count == 1)
    }
}

@MainActor
private final class FakePlaybackEngine: PlaybackEngine {
    struct Load {
        let url: URL
        let attemptID: PlaybackAttemptID
    }

    var eventHandler: ((PlaybackAttemptID, PlaybackEngineEvent) -> Void)?
    var volume: Float = 0
    private(set) var loads: [Load] = []
    private(set) var stopCount = 0

    func load(url: URL, attemptID: PlaybackAttemptID) {
        loads.append(Load(url: url, attemptID: attemptID))
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ event: PlaybackEngineEvent, attemptID: PlaybackAttemptID) {
        eventHandler?(attemptID, event)
    }
}

@MainActor
private final class FakePlaybackScheduler: PlaybackDeadlineScheduling {
    private(set) var scheduled: PlaybackDeadline?
    private(set) var cancelCount = 0
    private var handler: ((PlaybackDeadlineID) -> Void)?

    func schedule(
        _ deadline: PlaybackDeadline,
        handler: @escaping (PlaybackDeadlineID) -> Void
    ) {
        scheduled = deadline
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        scheduled = nil
        handler = nil
    }

    func fire() {
        guard let id = scheduled?.id else { return }
        scheduled = nil
        let callback = handler
        handler = nil
        callback?(id)
    }
}

@MainActor
private final class FakeConnectivitySource: PlaybackConnectivitySourcing {
    var handler: ((PlaybackConnectivity) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func emit(_ connectivity: PlaybackConnectivity) { handler?(connectivity) }
}

@MainActor
private final class FakeSleepWakeSource: PlaybackSleepWakeSourcing {
    var sleepHandler: (() -> Void)?
    var wakeHandler: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func sleep() { sleepHandler?() }
    func wake() { wakeHandler?() }
}

@MainActor
private final class FakePlaybackPreferences: PlaybackPreferenceStoring {
    var preferredQuality: StreamQuality {
        didSet { writeCount += 1 }
    }
    private(set) var writeCount = 0

    init(preferredQuality: StreamQuality) {
        self.preferredQuality = preferredQuality
    }
}
