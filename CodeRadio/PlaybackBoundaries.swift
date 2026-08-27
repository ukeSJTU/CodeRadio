import Foundation

@MainActor
protocol PlaybackEngine: AnyObject {
    var eventHandler: ((PlaybackAttemptID, PlaybackEngineEvent) -> Void)? { get set }
    var volume: Float { get set }

    func load(url: URL, attemptID: PlaybackAttemptID)
    func stop()
}

@MainActor
protocol PlaybackDeadlineScheduling: AnyObject {
    func schedule(
        _ deadline: PlaybackDeadline,
        handler: @escaping (PlaybackDeadlineID) -> Void
    )
    func cancel()
}

@MainActor
protocol PlaybackConnectivitySourcing: AnyObject {
    var handler: ((PlaybackConnectivity) -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
protocol PlaybackSleepWakeSourcing: AnyObject {
    var sleepHandler: (() -> Void)? { get set }
    var wakeHandler: (() -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
protocol PlaybackPreferenceStoring: AnyObject {
    var preferredQuality: StreamQuality { get set }
}
