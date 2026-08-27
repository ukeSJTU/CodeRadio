import Testing
@testable import CodeRadio

@Suite("Playback presentation")
@MainActor
struct PlaybackPresentationTests {
    @Test("Every playback phase has distinct controls, system state, and accessible menu text")
    func playbackPhaseMapping() {
        let cases: [(PlaybackPhase, String, String, PlaybackPrimaryAction, PlaybackSystemState)] = [
            (.stopped, "radio", "Code Radio, Stopped", .play, .stopped),
            (.connecting(.connecting), "ellipsis.circle", "Code Radio, Connecting", .stop, .interrupted),
            (.connecting(.buffering), "ellipsis.circle", "Code Radio, Buffering", .stop, .interrupted),
            (.playing, "waveform.circle.fill", "Code Radio, Playing", .stop, .playing),
            (.reconnecting, "ellipsis.circle", "Code Radio, Reconnecting", .stop, .interrupted),
            (.offline, "wifi.slash", "Code Radio, Offline", .stop, .interrupted),
            (
                .failed(.streamFailed),
                "exclamationmark.triangle.fill",
                "Code Radio, Playback failed",
                .stop,
                .stopped
            ),
        ]

        for (phase, icon, accessibilityLabel, action, systemState) in cases {
            let presentation = PlaybackPresentation(snapshot: snapshot(phase: phase))
            #expect(presentation.menuBarSystemImage == icon)
            #expect(presentation.menuBarAccessibilityLabel == accessibilityLabel)
            #expect(presentation.primaryAction == action)
            #expect(presentation.systemState == systemState)
            #expect(presentation.playbackRate == (phase == .playing ? 1 : 0))
        }
    }

    @Test("Failed playback exposes Retry without claiming fallback audio is playing")
    func failedStatusExposesRetry() {
        var failedSnapshot = snapshot(phase: .failed(.startupTimedOut))
        failedSnapshot.effectiveQuality = .low
        let presentation = PlaybackPresentation(snapshot: failedSnapshot)

        #expect(presentation.statusMessages.map(\.message) == ["Unable to start playback."])
        #expect(presentation.statusMessages.first?.showsRetry == true)
    }

    @Test("Temporary fallback wording follows observed playback")
    func fallbackStatusMatchesObservedPlayback() {
        var connectingSnapshot = snapshot(phase: .connecting(.connecting))
        connectingSnapshot.effectiveQuality = .low
        #expect(PlaybackPresentation(snapshot: connectingSnapshot).statusMessages.last?.message ==
            "Trying the 64 kbps stream. Your 128 kbps preference is unchanged.")

        connectingSnapshot.phase = .playing
        #expect(PlaybackPresentation(snapshot: connectingSnapshot).statusMessages.last?.message ==
            "Playing at 64 kbps. Your 128 kbps preference is unchanged.")
    }

    private func snapshot(phase: PlaybackPhase) -> PlaybackSnapshot {
        PlaybackSnapshot(
            intent: phase == .stopped ? .stopped : .playing,
            phase: phase,
            preferredQuality: .high,
            effectiveQuality: phase == .stopped ? nil : .high,
            hasPlayedSuccessfully: phase == .playing || phase == .reconnecting
        )
    }
}
