import Foundation

enum PlaybackPrimaryAction: Equatable, Sendable {
    case play
    case stop
}

enum PlaybackSystemState: Equatable, Sendable {
    case playing
    case interrupted
    case stopped
}

enum PlaybackStatusTone: Equatable, Sendable {
    case informational
    case warning
    case error
}

struct PlaybackStatusPresentation: Equatable, Sendable, Identifiable {
    let message: String
    let systemImage: String
    let tone: PlaybackStatusTone
    let showsRetry: Bool

    var id: String { "\(systemImage)|\(message)" }
}

struct PlaybackPresentation: Equatable, Sendable {
    let snapshot: PlaybackSnapshot

    var menuBarSystemImage: String {
        switch snapshot.phase {
        case .stopped:
            return "radio"
        case .connecting, .reconnecting:
            return "ellipsis.circle"
        case .playing:
            return "waveform.circle.fill"
        case .offline:
            return "wifi.slash"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var menuBarAccessibilityLabel: String {
        String(localized: "Code Radio, \(stateName)")
    }

    var primaryAction: PlaybackPrimaryAction {
        snapshot.intent == .stopped ? .play : .stop
    }

    var primarySystemImage: String {
        primaryAction == .play ? "play.fill" : "stop.fill"
    }

    var primaryAccessibilityLabel: String {
        primaryAction == .play
            ? String(localized: "Play Code Radio")
            : String(localized: "Stop Code Radio")
    }

    var primaryHelp: String {
        primaryAction == .play ? String(localized: "Play") : String(localized: "Stop")
    }

    var systemState: PlaybackSystemState {
        switch snapshot.phase {
        case .playing:
            return .playing
        case .connecting, .reconnecting, .offline:
            return .interrupted
        case .stopped, .failed:
            return .stopped
        }
    }

    var playbackRate: Double {
        snapshot.phase == .playing ? 1 : 0
    }

    var statusMessages: [PlaybackStatusPresentation] {
        var messages: [PlaybackStatusPresentation] = []
        if let phaseMessage {
            messages.append(phaseMessage)
        }
        if let fallbackMessage {
            messages.append(PlaybackStatusPresentation(
                message: fallbackMessage,
                systemImage: "arrow.down.circle.fill",
                tone: .informational,
                showsRetry: false
            ))
        }
        return messages
    }

    private var stateName: String {
        switch snapshot.phase {
        case .stopped:
            return String(localized: "Stopped")
        case .connecting(.connecting):
            return String(localized: "Connecting")
        case .connecting(.buffering):
            return String(localized: "Buffering")
        case .playing:
            return String(localized: "Playing")
        case .reconnecting:
            return String(localized: "Reconnecting")
        case .offline:
            return String(localized: "Offline")
        case .failed:
            return String(localized: "Playback failed")
        }
    }

    private var fallbackMessage: String? {
        guard snapshot.isUsingTemporaryFallback else { return nil }
        switch snapshot.phase {
        case .playing:
            return String(localized: "Playing at 64 kbps. Your 128 kbps preference is unchanged.")
        case .connecting, .reconnecting:
            return String(localized: "Trying the 64 kbps stream. Your 128 kbps preference is unchanged.")
        case .offline:
            return String(localized: "Recovery will use 64 kbps. Your 128 kbps preference is unchanged.")
        case .stopped, .failed:
            return nil
        }
    }

    private var phaseMessage: PlaybackStatusPresentation? {
        switch snapshot.phase {
        case .stopped, .playing:
            return nil
        case .connecting(.connecting):
            return status(
                String(localized: "Connecting…"),
                systemImage: "antenna.radiowaves.left.and.right",
                tone: .informational
            )
        case .connecting(.buffering):
            return status(
                String(localized: "Buffering…"),
                systemImage: "ellipsis.circle",
                tone: .informational
            )
        case .reconnecting:
            return status(
                String(localized: "Reconnecting…"),
                systemImage: "arrow.clockwise.circle.fill",
                tone: .warning
            )
        case .offline:
            return status(
                String(localized: "No network connection. Playback will resume automatically."),
                systemImage: "wifi.slash",
                tone: .warning
            )
        case .failed(let reason):
            return PlaybackStatusPresentation(
                message: failureMessage(for: reason),
                systemImage: "exclamationmark.triangle.fill",
                tone: .error,
                showsRetry: true
            )
        }
    }

    private func failureMessage(for reason: PlaybackFailureReason) -> String {
        switch reason {
        case .startupTimedOut:
            return String(localized: "Unable to start playback.")
        case .stalled:
            return String(localized: "Playback could not be restored.")
        case .sourceUnsupported:
            return String(localized: "The selected stream format is unavailable.")
        case .streamFailed:
            return String(localized: "The Code Radio stream is currently unavailable.")
        }
    }

    private func status(
        _ message: String,
        systemImage: String,
        tone: PlaybackStatusTone
    ) -> PlaybackStatusPresentation {
        PlaybackStatusPresentation(
            message: message,
            systemImage: systemImage,
            tone: tone,
            showsRetry: false
        )
    }
}
