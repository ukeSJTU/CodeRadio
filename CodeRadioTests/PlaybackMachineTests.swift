import Foundation
import Testing
@testable import CodeRadio

@Suite("Playback state machine")
@MainActor
struct PlaybackMachineTests {
    @Test("Play starts a preferred-quality connection without claiming audio is playing")
    func playStartsConnecting() {
        var machine = PlaybackMachine(preferredQuality: .high)

        let effects = machine.handle(.play)

        #expect(machine.snapshot.intent == .playing)
        #expect(machine.snapshot.phase == .connecting(.connecting))
        #expect(machine.snapshot.effectiveQuality == .high)
        #expect(effects == [
            .load(.init(id: .init(rawValue: 1), quality: .high)),
            .schedule(.init(
                id: .init(rawValue: 1),
                kind: .startup(attemptID: .init(rawValue: 1)),
                duration: .seconds(15)
            )),
        ])
    }

    @Test("Stop clears playback intent and cancels recovery")
    func stopCancelsRecovery() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)

        let effects = machine.handle(.stop)

        #expect(machine.snapshot.intent == .stopped)
        #expect(machine.snapshot.phase == .stopped)
        #expect(machine.snapshot.effectiveQuality == nil)
        #expect(effects == [.cancelDeadline, .stopEngine])
    }

    @Test("Observed engine events distinguish buffering from actual playback")
    func observedEventsDriveVisibleState() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        let attemptID = PlaybackAttemptID(rawValue: 1)

        let waitingEffects = machine.handle(.engine(attemptID, .waiting))
        #expect(machine.snapshot.phase == .connecting(.buffering))
        #expect(waitingEffects.isEmpty)

        let playingEffects = machine.handle(.engine(attemptID, .playing))
        #expect(machine.snapshot.phase == .playing)
        #expect(machine.snapshot.hasPlayedSuccessfully)
        #expect(playingEffects == [
            .cancelDeadline,
            .schedule(.init(
                id: .init(rawValue: 2),
                kind: .stability(attemptID: attemptID),
                duration: .seconds(30)
            )),
        ])
    }

    @Test("Waiting after playback begins enters reconnecting with a stall deadline")
    func stallStartsReconnect() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        let attemptID = PlaybackAttemptID(rawValue: 1)
        _ = machine.handle(.engine(attemptID, .playing))

        let effects = machine.handle(.engine(attemptID, .waiting))

        #expect(machine.snapshot.phase == .reconnecting)
        #expect(effects == [
            .cancelDeadline,
            .schedule(.init(
                id: .init(rawValue: 3),
                kind: .stall(attemptID: attemptID),
                duration: .seconds(10)
            )),
        ])
    }

    @Test("Transient failures use bounded backoff and only lower the effective quality")
    func transientFailuresUseBoundedFallback() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)

        let retryOne = machine.handle(.engine(.init(rawValue: 1), .failed(.transient)))
        #expect(retryOne == [
            .cancelDeadline,
            .stopEngine,
            .schedule(.init(
                id: .init(rawValue: 2),
                kind: .retry(quality: .high),
                duration: .seconds(1)
            )),
        ])
        _ = machine.handle(.deadlineElapsed(.init(rawValue: 2)))

        let retryTwo = machine.handle(.engine(.init(rawValue: 2), .failed(.transient)))
        #expect(retryTwo.last == .schedule(.init(
            id: .init(rawValue: 4),
            kind: .retry(quality: .low),
            duration: .seconds(3)
        )))
        let lowAttempt = machine.handle(.deadlineElapsed(.init(rawValue: 4)))
        #expect(lowAttempt.first == .load(.init(id: .init(rawValue: 3), quality: .low)))
        #expect(machine.snapshot.preferredQuality == .high)
        #expect(machine.snapshot.effectiveQuality == .low)
        #expect(machine.snapshot.isUsingTemporaryFallback)

        let retryThree = machine.handle(.engine(.init(rawValue: 3), .failed(.transient)))
        #expect(retryThree.last == .schedule(.init(
            id: .init(rawValue: 6),
            kind: .retry(quality: .low),
            duration: .seconds(8)
        )))
        _ = machine.handle(.deadlineElapsed(.init(rawValue: 6)))

        let exhausted = machine.handle(.engine(.init(rawValue: 4), .failed(.transient)))
        #expect(machine.snapshot.phase == .failed(.streamFailed))
        #expect(machine.snapshot.intent == .playing)
        #expect(exhausted == [.cancelDeadline, .stopEngine])
    }

    @Test("Network loss does not interrupt buffered audio but suspends recovery once it stalls")
    func offlineWaitsForObservedStall() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        let attemptID = PlaybackAttemptID(rawValue: 1)
        _ = machine.handle(.engine(attemptID, .playing))

        let pathEffects = machine.handle(.connectivityChanged(.unavailable))
        #expect(machine.snapshot.phase == .playing)
        #expect(pathEffects.isEmpty)

        let stallEffects = machine.handle(.engine(attemptID, .waiting))
        #expect(machine.snapshot.phase == .offline)
        #expect(stallEffects == [.cancelDeadline, .stopEngine])
    }

    @Test("A connectivity flap does not restart audio that is still playing")
    func connectivityFlapKeepsObservedPlayback() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        _ = machine.handle(.engine(.init(rawValue: 1), .playing))
        _ = machine.handle(.connectivityChanged(.unavailable))

        let effects = machine.handle(.connectivityChanged(.available))

        #expect(machine.snapshot.phase == .playing)
        #expect(effects.isEmpty)
    }

    @Test("A player failure during a confirmed outage waits offline instead of retrying")
    func playerFailureDuringOutageBecomesOffline() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        _ = machine.handle(.engine(.init(rawValue: 1), .playing))
        _ = machine.handle(.connectivityChanged(.unavailable))

        let effects = machine.handle(.engine(.init(rawValue: 1), .failed(.transient)))

        #expect(machine.snapshot.phase == .offline)
        #expect(effects == [.cancelDeadline, .stopEngine])
    }

    @Test("Stop invalidates late engine and deadline events")
    func stopInvalidatesLateEvents() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        _ = machine.handle(.stop)

        #expect(machine.handle(.engine(.init(rawValue: 1), .playing)).isEmpty)
        #expect(machine.handle(.deadlineElapsed(.init(rawValue: 1))).isEmpty)
        #expect(machine.snapshot.phase == .stopped)
    }

    @Test("Online recovery waits for a stable connectivity window")
    func onlineRecoveryIsDebounced() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.connectivityChanged(.unavailable))
        #expect(machine.handle(.play).isEmpty)
        #expect(machine.snapshot.phase == .offline)

        let onlineEffects = machine.handle(.connectivityChanged(.available))
        #expect(onlineEffects == [
            .cancelDeadline,
            .stopEngine,
            .schedule(.init(
                id: .init(rawValue: 1),
                kind: .connectivityStability(.offlineRecovery),
                duration: .seconds(1)
            )),
        ])

        let connectionEffects = machine.handle(.deadlineElapsed(.init(rawValue: 1)))
        #expect(connectionEffects.first == .load(.init(id: .init(rawValue: 1), quality: .high)))
    }

    @Test("Offline recovery survives an intermediate unknown path state")
    func offlineRecoverySurvivesUnknownConnectivity() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.connectivityChanged(.unavailable))
        _ = machine.handle(.play)

        #expect(machine.handle(.connectivityChanged(.unknown)).isEmpty)
        let effects = machine.handle(.connectivityChanged(.available))

        #expect(machine.snapshot.phase == .connecting(.connecting))
        #expect(effects == [
            .cancelDeadline,
            .stopEngine,
            .schedule(.init(
                id: .init(rawValue: 1),
                kind: .connectivityStability(.offlineRecovery),
                duration: .seconds(1)
            )),
        ])
    }

    @Test("Offline recovery requires a continuous available-path window")
    func offlineRecoveryRestartsAfterUnknownConnectivity() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.connectivityChanged(.unavailable))
        _ = machine.handle(.play)
        let firstWindow = machine.handle(.connectivityChanged(.available))
        let firstDeadline = scheduledDeadline(from: firstWindow)

        #expect(machine.handle(.connectivityChanged(.unknown)) == [.cancelDeadline])
        #expect(machine.snapshot.phase == .offline)

        let secondWindow = machine.handle(.connectivityChanged(.available))
        let secondDeadline = scheduledDeadline(from: secondWindow)
        #expect(secondDeadline.id != firstDeadline.id)
        #expect(machine.handle(.deadlineElapsed(firstDeadline.id)).isEmpty)
        #expect(machine.handle(.deadlineElapsed(secondDeadline.id)).first ==
            .load(.init(id: .init(rawValue: 1), quality: .high)))
    }

    @Test("A low-quality preference never upgrades during recovery")
    func lowPreferenceNeverUpgrades() {
        var machine = PlaybackMachine(preferredQuality: .low)
        var loadedQualities: [StreamQuality] = []

        loadedQualities.append(loadQuality(from: machine.handle(.play)))
        for (attemptID, retryDeadlineID) in [(1, 2), (2, 4), (3, 6)] {
            _ = machine.handle(.engine(.init(rawValue: UInt64(attemptID)), .failed(.transient)))
            loadedQualities.append(loadQuality(from: machine.handle(
                .deadlineElapsed(.init(rawValue: UInt64(retryDeadlineID)))
            )))
        }

        #expect(loadedQualities == [.low, .low, .low, .low])
    }

    @Test("An unsupported high-quality source falls back immediately")
    func unsupportedHighFallsBackImmediately() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)

        let effects = machine.handle(.engine(
            .init(rawValue: 1),
            .failed(.unsupportedOrInvalidSource)
        ))

        #expect(effects == [
            .cancelDeadline,
            .stopEngine,
            .load(.init(id: .init(rawValue: 2), quality: .low)),
            .schedule(.init(
                id: .init(rawValue: 2),
                kind: .startup(attemptID: .init(rawValue: 2)),
                duration: .seconds(15)
            )),
        ])
        #expect(machine.snapshot.preferredQuality == .high)
        #expect(machine.snapshot.isUsingTemporaryFallback)
    }

    @Test("An unsupported low-quality source fails without wasting retry budget")
    func unsupportedLowFailsImmediately() {
        var machine = PlaybackMachine(preferredQuality: .low)
        _ = machine.handle(.play)

        let effects = machine.handle(.engine(
            .init(rawValue: 1),
            .failed(.unsupportedOrInvalidSource)
        ))

        #expect(machine.snapshot.phase == .failed(.sourceUnsupported))
        #expect(effects == [.cancelDeadline, .stopEngine])
    }

    @Test("Retry preserves session history but starts from the saved preference")
    func retryPreservesSessionHistory() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        _ = machine.handle(.engine(.init(rawValue: 1), .playing))

        for (attemptID, retryDeadlineID) in [(1, 3), (2, 5), (3, 7)] {
            _ = machine.handle(.engine(.init(rawValue: UInt64(attemptID)), .failed(.transient)))
            _ = machine.handle(.deadlineElapsed(.init(rawValue: UInt64(retryDeadlineID))))
        }
        _ = machine.handle(.engine(.init(rawValue: 4), .failed(.transient)))
        #expect(machine.snapshot.phase == .failed(.streamFailed))

        let effects = machine.handle(.retry)

        #expect(machine.snapshot.hasPlayedSuccessfully)
        #expect(machine.snapshot.phase == .reconnecting)
        #expect(machine.snapshot.effectiveQuality == .high)
        #expect(effects.first == .load(.init(id: .init(rawValue: 5), quality: .high)))
    }

    @Test("Changing quality while stopped only persists the preference")
    func stoppedQualityChangeDoesNotConnect() {
        var machine = PlaybackMachine(preferredQuality: .high)

        let effects = machine.handle(.preferredQualityChanged(.low))

        #expect(machine.snapshot.phase == .stopped)
        #expect(machine.snapshot.preferredQuality == .low)
        #expect(effects == [.persistPreferredQuality(.low)])
    }

    @Test("Changing quality with active intent starts a fresh connection cycle")
    func activeQualityChangeReconnects() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)

        let effects = machine.handle(.preferredQualityChanged(.low))

        #expect(machine.snapshot.intent == .playing)
        #expect(machine.snapshot.preferredQuality == .low)
        #expect(machine.snapshot.effectiveQuality == .low)
        #expect(effects == [
            .persistPreferredQuality(.low),
            .cancelDeadline,
            .stopEngine,
            .load(.init(id: .init(rawValue: 2), quality: .low)),
            .schedule(.init(
                id: .init(rawValue: 2),
                kind: .startup(attemptID: .init(rawValue: 2)),
                duration: .seconds(15)
            )),
        ])
    }

    @Test("Wake resumes intent even while connectivity is still unknown")
    func wakeResumesWithUnknownConnectivity() {
        var machine = PlaybackMachine(preferredQuality: .high)
        _ = machine.handle(.play)
        #expect(machine.handle(.willSleep) == [.cancelDeadline, .stopEngine])

        let wakeEffects = machine.handle(.didWake)
        #expect(wakeEffects == [.schedule(.init(
            id: .init(rawValue: 2),
            kind: .connectivityStability(.wake),
            duration: .seconds(1)
        ))])

        let resumedEffects = machine.handle(.deadlineElapsed(.init(rawValue: 2)))
        #expect(resumedEffects.first == .load(.init(id: .init(rawValue: 2), quality: .high)))
    }

    @Test("Only stable playback resets an exhausted recovery budget")
    func stablePlaybackResetsBudget() {
        let policy = PlaybackPolicy(
            maximumAttempts: 2,
            retryDelays: [.seconds(1)],
            startupTimeout: .seconds(15),
            stallTimeout: .seconds(10),
            stabilityWindow: .seconds(30),
            connectivityStabilityWindow: .seconds(1)
        )
        var machine = PlaybackMachine(preferredQuality: .low, policy: policy)
        _ = machine.handle(.play)
        _ = machine.handle(.engine(.init(rawValue: 1), .failed(.transient)))
        _ = machine.handle(.deadlineElapsed(.init(rawValue: 2)))
        _ = machine.handle(.engine(.init(rawValue: 2), .playing))
        _ = machine.handle(.deadlineElapsed(.init(rawValue: 4)))
        _ = machine.handle(.engine(.init(rawValue: 2), .waiting))

        let effects = machine.handle(.deadlineElapsed(.init(rawValue: 5)))

        #expect(machine.snapshot.phase == .reconnecting)
        #expect(effects.last == .schedule(.init(
            id: .init(rawValue: 6),
            kind: .retry(quality: .low),
            duration: .seconds(1)
        )))
    }

    private func loadQuality(from effects: [PlaybackEffect]) -> StreamQuality {
        for effect in effects {
            if case .load(let attempt) = effect { return attempt.quality }
        }
        Issue.record("Expected a load effect")
        return .high
    }

    private func scheduledDeadline(from effects: [PlaybackEffect]) -> PlaybackDeadline {
        for effect in effects {
            if case .schedule(let deadline) = effect { return deadline }
        }
        Issue.record("Expected a scheduled deadline")
        return .init(
            id: .init(rawValue: 0),
            kind: .connectivityStability(.offlineRecovery),
            duration: .zero
        )
    }
}
