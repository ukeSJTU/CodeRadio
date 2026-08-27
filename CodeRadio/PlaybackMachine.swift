import Foundation

enum PlaybackIntent: Equatable, Sendable {
    case stopped
    case playing
}

enum PlaybackConnectingDetail: Equatable, Sendable {
    case connecting
    case buffering
}

enum PlaybackPhase: Equatable, Sendable {
    case stopped
    case connecting(PlaybackConnectingDetail)
    case playing
    case reconnecting
    case offline
    case failed(PlaybackFailureReason)
}

enum PlaybackFailureReason: Equatable, Sendable {
    case startupTimedOut
    case stalled
    case sourceUnsupported
    case streamFailed
}

enum PlaybackEngineFailure: Equatable, Sendable {
    case cancelled
    case unsupportedOrInvalidSource
    case transient
    case unknown
}

struct PlaybackAttemptID: Hashable, Sendable {
    let rawValue: UInt64
}

struct PlaybackDeadlineID: Hashable, Sendable {
    let rawValue: UInt64
}

struct PlaybackAttempt: Equatable, Sendable {
    let id: PlaybackAttemptID
    let quality: StreamQuality
}

enum PlaybackDeadlineKind: Equatable, Sendable {
    case startup(attemptID: PlaybackAttemptID)
    case stall(attemptID: PlaybackAttemptID)
    case stability(attemptID: PlaybackAttemptID)
    case retry(quality: StreamQuality)
    case connectivityStability(PlaybackConnectivityStabilityPurpose)
}

enum PlaybackConnectivityStabilityPurpose: Equatable, Sendable {
    case offlineRecovery
    case wake
}

struct PlaybackDeadline: Equatable, Sendable {
    let id: PlaybackDeadlineID
    let kind: PlaybackDeadlineKind
    let duration: Duration
}

enum PlaybackEffect: Equatable, Sendable {
    case load(PlaybackAttempt)
    case schedule(PlaybackDeadline)
    case cancelDeadline
    case stopEngine
    case persistPreferredQuality(StreamQuality)
}

enum PlaybackEngineEvent: Equatable, Sendable {
    case waiting
    case playing
    case failed(PlaybackEngineFailure)
}

enum PlaybackConnectivity: Equatable, Sendable {
    case unknown
    case available
    case unavailable
}

enum PlaybackEvent: Equatable, Sendable {
    case play
    case stop
    case retry
    case preferredQualityChanged(StreamQuality)
    case engine(PlaybackAttemptID, PlaybackEngineEvent)
    case deadlineElapsed(PlaybackDeadlineID)
    case connectivityChanged(PlaybackConnectivity)
    case willSleep
    case didWake
}

struct PlaybackSnapshot: Equatable, Sendable {
    var intent: PlaybackIntent
    var phase: PlaybackPhase
    var preferredQuality: StreamQuality
    var effectiveQuality: StreamQuality?
    var hasPlayedSuccessfully: Bool

    var isUsingTemporaryFallback: Bool {
        preferredQuality == .high && effectiveQuality == .low
    }
}

struct PlaybackPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let retryDelays: [Duration]
    let startupTimeout: Duration
    let stallTimeout: Duration
    let stabilityWindow: Duration
    let connectivityStabilityWindow: Duration

    static let standard = PlaybackPolicy(
        maximumAttempts: 4,
        retryDelays: [.seconds(1), .seconds(3), .seconds(8)],
        startupTimeout: .seconds(15),
        stallTimeout: .seconds(10),
        stabilityWindow: .seconds(30),
        connectivityStabilityWindow: .seconds(1)
    )
}

struct PlaybackMachine {
    private enum EngineStage {
        case idle
        case loading
        case waiting
        case playing
        case stalled
    }

    private let policy: PlaybackPolicy
    private(set) var snapshot: PlaybackSnapshot

    private var connectivity = PlaybackConnectivity.unknown
    private var isSleeping = false
    private var engineStage = EngineStage.idle
    private var activeAttempt: PlaybackAttempt?
    private var activeDeadline: PlaybackDeadline?
    private var attemptsUsed = 0
    private var fallbackPinned = false
    private var nextAttemptRawValue: UInt64 = 1
    private var nextDeadlineRawValue: UInt64 = 1

    init(
        preferredQuality: StreamQuality,
        policy: PlaybackPolicy = .standard
    ) {
        self.policy = policy
        snapshot = PlaybackSnapshot(
            intent: .stopped,
            phase: .stopped,
            preferredQuality: preferredQuality,
            effectiveQuality: nil,
            hasPlayedSuccessfully: false
        )
    }

    mutating func handle(_ event: PlaybackEvent) -> [PlaybackEffect] {
        switch event {
        case .play:
            return handlePlay()
        case .stop:
            return handleStop()
        case .retry:
            return handleRetry()
        case .preferredQualityChanged(let quality):
            return handlePreferredQualityChange(quality)
        case .engine(let attemptID, let engineEvent):
            return handleEngineEvent(engineEvent, for: attemptID)
        case .deadlineElapsed(let deadlineID):
            return handleDeadline(deadlineID)
        case .connectivityChanged(let connectivity):
            return handleConnectivityChange(connectivity)
        case .willSleep:
            return handleSleep()
        case .didWake:
            return handleWake()
        }
    }

    private mutating func handlePlay() -> [PlaybackEffect] {
        guard snapshot.intent == .stopped else { return [] }
        snapshot.intent = .playing
        snapshot.hasPlayedSuccessfully = false
        snapshot.effectiveQuality = nil
        fallbackPinned = false
        attemptsUsed = 0

        guard !isSleeping else { return [] }
        guard connectivity != .unavailable else {
            snapshot.phase = .offline
            return []
        }
        return beginAttempt(quality: snapshot.preferredQuality, countsTowardBudget: true)
    }

    private mutating func handleStop() -> [PlaybackEffect] {
        guard snapshot.intent == .playing else { return [] }
        snapshot.intent = .stopped
        snapshot.phase = .stopped
        snapshot.effectiveQuality = nil
        snapshot.hasPlayedSuccessfully = false
        fallbackPinned = false
        attemptsUsed = 0
        invalidateAttemptAndDeadline()
        return [.cancelDeadline, .stopEngine]
    }

    private mutating func handleRetry() -> [PlaybackEffect] {
        guard snapshot.intent == .playing,
              case .failed = snapshot.phase
        else { return [] }

        attemptsUsed = 0
        fallbackPinned = false
        snapshot.effectiveQuality = nil
        guard !isSleeping, connectivity != .unavailable else {
            snapshot.phase = connectivity == .unavailable ? .offline : derivedConnectingPhase()
            return []
        }
        return beginAttempt(quality: snapshot.preferredQuality, countsTowardBudget: true)
    }

    private mutating func handlePreferredQualityChange(
        _ quality: StreamQuality
    ) -> [PlaybackEffect] {
        guard quality != snapshot.preferredQuality else { return [] }
        snapshot.preferredQuality = quality
        var effects: [PlaybackEffect] = [.persistPreferredQuality(quality)]
        guard snapshot.intent == .playing else { return effects }

        invalidateAttemptAndDeadline()
        effects.append(contentsOf: [.cancelDeadline, .stopEngine])
        attemptsUsed = 0
        fallbackPinned = false
        snapshot.effectiveQuality = nil

        guard !isSleeping, connectivity != .unavailable else {
            snapshot.phase = connectivity == .unavailable ? .offline : derivedConnectingPhase()
            return effects
        }
        effects.append(contentsOf: beginAttempt(quality: quality, countsTowardBudget: true))
        return effects
    }

    private mutating func handleEngineEvent(
        _ event: PlaybackEngineEvent,
        for attemptID: PlaybackAttemptID
    ) -> [PlaybackEffect] {
        guard activeAttempt?.id == attemptID else { return [] }
        if connectivity == .unavailable {
            switch event {
            case .playing:
                break
            case .waiting, .failed:
                return becomeOffline()
            }
        }

        switch event {
        case .waiting:
            if connectivity == .unavailable {
                return becomeOffline()
            }
            guard engineStage != .waiting, engineStage != .stalled else { return [] }
            let wasPlaying = engineStage == .playing
            engineStage = wasPlaying ? .stalled : .waiting
            snapshot.phase = derivedConnectingPhase(buffering: !snapshot.hasPlayedSuccessfully)

            guard wasPlaying else { return [] }
            if attemptsUsed == 0 { attemptsUsed = 1 }
            return replaceDeadline(
                kind: .stall(attemptID: attemptID),
                duration: policy.stallTimeout
            )
        case .playing:
            guard engineStage != .playing else { return [] }
            engineStage = .playing
            snapshot.phase = .playing
            snapshot.hasPlayedSuccessfully = true
            return replaceDeadline(
                kind: .stability(attemptID: attemptID),
                duration: policy.stabilityWindow
            )
        case .failed(let failure):
            switch failure {
            case .cancelled:
                return []
            case .unsupportedOrInvalidSource:
                return failCurrentAttempt(reason: .sourceUnsupported, skipToLow: true)
            case .transient, .unknown:
                return failCurrentAttempt(reason: .streamFailed)
            }
        }
    }

    private mutating func handleDeadline(
        _ deadlineID: PlaybackDeadlineID
    ) -> [PlaybackEffect] {
        guard let deadline = activeDeadline, deadline.id == deadlineID else { return [] }
        activeDeadline = nil

        switch deadline.kind {
        case .startup(let attemptID):
            guard activeAttempt?.id == attemptID else { return [] }
            return failCurrentAttempt(reason: .startupTimedOut)
        case .stall(let attemptID):
            guard activeAttempt?.id == attemptID else { return [] }
            return failCurrentAttempt(reason: .stalled)
        case .stability(let attemptID):
            guard activeAttempt?.id == attemptID else { return [] }
            attemptsUsed = 0
            return []
        case .retry(let quality):
            guard snapshot.intent == .playing,
                  connectivity != .unavailable,
                  !isSleeping
            else { return [] }
            return beginAttempt(quality: quality, countsTowardBudget: true)
        case .connectivityStability(let purpose):
            guard snapshot.intent == .playing,
                  !isSleeping
            else { return [] }
            switch purpose {
            case .offlineRecovery:
                guard connectivity == .available else { return [] }
            case .wake:
                guard connectivity != .unavailable else { return [] }
            }
            let quality = fallbackPinned ? StreamQuality.low : snapshot.preferredQuality
            return beginAttempt(quality: quality, countsTowardBudget: true)
        }
    }

    private mutating func handleConnectivityChange(
        _ newConnectivity: PlaybackConnectivity
    ) -> [PlaybackEffect] {
        let wasOffline = snapshot.phase == .offline
        connectivity = newConnectivity

        guard snapshot.intent == .playing else { return [] }
        if newConnectivity == .unavailable {
            if engineStage == .playing { return [] }
            return becomeOffline()
        }
        if newConnectivity == .unknown,
           activeDeadline?.kind == .connectivityStability(.offlineRecovery)
        {
            activeDeadline = nil
            snapshot.phase = .offline
            return [.cancelDeadline]
        }
        guard wasOffline, newConnectivity == .available else { return [] }
        guard engineStage != .playing else { return [] }

        invalidateAttemptAndDeadline()
        attemptsUsed = 0
        snapshot.phase = derivedConnectingPhase()
        return [
            .cancelDeadline,
            .stopEngine,
            scheduleDeadline(
                kind: .connectivityStability(.offlineRecovery),
                duration: policy.connectivityStabilityWindow
            ),
        ]
    }

    private mutating func handleSleep() -> [PlaybackEffect] {
        guard !isSleeping else { return [] }
        isSleeping = true
        guard snapshot.intent == .playing else { return [] }
        if activeAttempt != nil, attemptsUsed > 0 {
            attemptsUsed -= 1
        }
        invalidateAttemptAndDeadline(preservingAttempts: true)
        return [.cancelDeadline, .stopEngine]
    }

    private mutating func handleWake() -> [PlaybackEffect] {
        guard isSleeping else { return [] }
        isSleeping = false
        guard snapshot.intent == .playing else { return [] }
        if case .failed = snapshot.phase { return [] }
        guard connectivity != .unavailable else {
            snapshot.phase = .offline
            return []
        }

        snapshot.phase = derivedConnectingPhase()
        return [scheduleDeadline(
            kind: .connectivityStability(.wake),
            duration: policy.connectivityStabilityWindow
        )]
    }

    private mutating func failCurrentAttempt(
        reason: PlaybackFailureReason,
        skipToLow: Bool = false
    ) -> [PlaybackEffect] {
        guard let failedAttempt = activeAttempt else { return [] }
        if attemptsUsed == 0 { attemptsUsed = 1 }
        activeAttempt = nil
        activeDeadline = nil
        engineStage = .idle

        var effects: [PlaybackEffect] = [.cancelDeadline, .stopEngine]

        if skipToLow, failedAttempt.quality == .low {
            snapshot.phase = .failed(reason)
            return effects
        }

        if skipToLow, failedAttempt.quality == .high, attemptsUsed < policy.maximumAttempts {
            fallbackPinned = true
            effects.append(contentsOf: beginAttempt(quality: .low, countsTowardBudget: true))
            return effects
        }

        guard attemptsUsed < policy.maximumAttempts else {
            snapshot.phase = .failed(reason)
            return effects
        }

        let nextAttemptNumber = attemptsUsed + 1
        let nextQuality = quality(forAttemptNumber: nextAttemptNumber)
        if nextQuality == .low, snapshot.preferredQuality == .high {
            fallbackPinned = true
        }
        snapshot.phase = derivedConnectingPhase()
        let delay = policy.retryDelays[attemptsUsed - 1]
        effects.append(scheduleDeadline(kind: .retry(quality: nextQuality), duration: delay))
        return effects
    }

    private mutating func beginAttempt(
        quality: StreamQuality,
        countsTowardBudget: Bool
    ) -> [PlaybackEffect] {
        if countsTowardBudget { attemptsUsed += 1 }
        let attempt = PlaybackAttempt(
            id: PlaybackAttemptID(rawValue: nextAttemptRawValue),
            quality: quality
        )
        nextAttemptRawValue += 1
        activeAttempt = attempt
        engineStage = .loading
        snapshot.effectiveQuality = quality
        snapshot.phase = derivedConnectingPhase()

        let deadline = makeDeadline(
            kind: .startup(attemptID: attempt.id),
            duration: policy.startupTimeout
        )
        activeDeadline = deadline
        return [.load(attempt), .schedule(deadline)]
    }

    private mutating func replaceDeadline(
        kind: PlaybackDeadlineKind,
        duration: Duration
    ) -> [PlaybackEffect] {
        activeDeadline = nil
        return [.cancelDeadline, scheduleDeadline(kind: kind, duration: duration)]
    }

    private mutating func scheduleDeadline(
        kind: PlaybackDeadlineKind,
        duration: Duration
    ) -> PlaybackEffect {
        let deadline = makeDeadline(kind: kind, duration: duration)
        activeDeadline = deadline
        return .schedule(deadline)
    }

    private mutating func makeDeadline(
        kind: PlaybackDeadlineKind,
        duration: Duration
    ) -> PlaybackDeadline {
        defer { nextDeadlineRawValue += 1 }
        return PlaybackDeadline(
            id: PlaybackDeadlineID(rawValue: nextDeadlineRawValue),
            kind: kind,
            duration: duration
        )
    }

    private func quality(forAttemptNumber attemptNumber: Int) -> StreamQuality {
        if snapshot.preferredQuality == .low || fallbackPinned { return .low }
        return attemptNumber <= 2 ? .high : .low
    }

    private func derivedConnectingPhase(buffering: Bool = false) -> PlaybackPhase {
        if snapshot.hasPlayedSuccessfully { return .reconnecting }
        return .connecting(buffering ? .buffering : .connecting)
    }

    private mutating func becomeOffline() -> [PlaybackEffect] {
        snapshot.phase = .offline
        invalidateAttemptAndDeadline(preservingAttempts: true)
        return [.cancelDeadline, .stopEngine]
    }

    private mutating func invalidateAttemptAndDeadline(
        preservingAttempts: Bool = false
    ) {
        activeAttempt = nil
        activeDeadline = nil
        engineStage = .idle
        if !preservingAttempts { attemptsUsed = 0 }
    }
}
