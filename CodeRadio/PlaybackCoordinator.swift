import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    private(set) var snapshot: PlaybackSnapshot

    @ObservationIgnored var snapshotDidChange: ((PlaybackSnapshot, PlaybackSnapshot) -> Void)?
    @ObservationIgnored private var machine: PlaybackMachine
    @ObservationIgnored private let engine: any PlaybackEngine
    @ObservationIgnored private let scheduler: any PlaybackDeadlineScheduling
    @ObservationIgnored private let connectivity: any PlaybackConnectivitySourcing
    @ObservationIgnored private let sleepWake: any PlaybackSleepWakeSourcing
    @ObservationIgnored private let preferences: any PlaybackPreferenceStoring
    @ObservationIgnored private let resolver: StreamURLResolver
    @ObservationIgnored private var mounts: [StreamMount] = []
    @ObservationIgnored private var isShutdown = false

    convenience init(
        engine: any PlaybackEngine,
        scheduler: any PlaybackDeadlineScheduling,
        connectivity: any PlaybackConnectivitySourcing,
        sleepWake: any PlaybackSleepWakeSourcing,
        preferences: any PlaybackPreferenceStoring
    ) {
        self.init(
            engine: engine,
            scheduler: scheduler,
            connectivity: connectivity,
            sleepWake: sleepWake,
            preferences: preferences,
            resolver: StreamURLResolver(),
            policy: .standard
        )
    }

    init(
        engine: any PlaybackEngine,
        scheduler: any PlaybackDeadlineScheduling,
        connectivity: any PlaybackConnectivitySourcing,
        sleepWake: any PlaybackSleepWakeSourcing,
        preferences: any PlaybackPreferenceStoring,
        resolver: StreamURLResolver,
        policy: PlaybackPolicy
    ) {
        self.engine = engine
        self.scheduler = scheduler
        self.connectivity = connectivity
        self.sleepWake = sleepWake
        self.preferences = preferences
        self.resolver = resolver
        machine = PlaybackMachine(
            preferredQuality: preferences.preferredQuality,
            policy: policy
        )
        snapshot = machine.snapshot

        engine.eventHandler = { [weak self] attemptID, event in
            self?.receive(.engine(attemptID, event))
        }
        connectivity.handler = { [weak self] connectivity in
            self?.receive(.connectivityChanged(connectivity))
        }
        sleepWake.sleepHandler = { [weak self] in
            self?.receive(.willSleep)
        }
        sleepWake.wakeHandler = { [weak self] in
            self?.receive(.didWake)
        }
        connectivity.start()
        sleepWake.start()
    }

    func play() {
        receive(.play)
    }

    func stop() {
        receive(.stop)
    }

    func retry() {
        receive(.retry)
    }

    func setPreferredQuality(_ quality: StreamQuality) {
        receive(.preferredQualityChanged(quality))
    }

    func setVolume(_ volume: Float) {
        engine.volume = volume
    }

    func updateMounts(_ mounts: [StreamMount]) {
        guard !isShutdown else { return }
        self.mounts = mounts
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        scheduler.cancel()
        engine.stop()
        connectivity.stop()
        sleepWake.stop()
        engine.eventHandler = nil
        connectivity.handler = nil
        sleepWake.sleepHandler = nil
        sleepWake.wakeHandler = nil
        snapshotDidChange = nil
    }

    private func receive(_ event: PlaybackEvent) {
        guard !isShutdown else { return }
        let previousSnapshot = snapshot
        let effects = machine.handle(event)
        snapshot = machine.snapshot
        if snapshot != previousSnapshot {
            snapshotDidChange?(previousSnapshot, snapshot)
        }
        execute(effects)
    }

    private func execute(_ effects: [PlaybackEffect]) {
        for effect in effects {
            switch effect {
            case .load(let attempt):
                let url = resolver.url(for: attempt.quality, mounts: mounts)
                engine.load(url: url, attemptID: attempt.id)
            case .schedule(let deadline):
                scheduler.schedule(deadline) { [weak self] deadlineID in
                    self?.receive(.deadlineElapsed(deadlineID))
                }
            case .cancelDeadline:
                scheduler.cancel()
            case .stopEngine:
                engine.stop()
            case .persistPreferredQuality(let quality):
                preferences.preferredQuality = quality
            }
        }
    }
}
