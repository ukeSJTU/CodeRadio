import AppKit
import AVFoundation
import Foundation
import Network

@MainActor
final class AVPlayerPlaybackEngine: PlaybackEngine {
    var eventHandler: ((PlaybackAttemptID, PlaybackEngineEvent) -> Void)?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    private let player = AVPlayer()
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?

    func load(url: URL, attemptID: PlaybackAttemptID) {
        clearCurrentItem()

        let item = AVPlayerItem(url: url)
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
            [weak self] item, _ in
            guard item.status == .failed else { return }
            let failure = Self.classify(item.error)
            Task { @MainActor [weak self] in
                self?.eventHandler?(attemptID, .failed(failure))
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] player, _ in
            let event: PlaybackEngineEvent?
            switch player.timeControlStatus {
            case .playing:
                event = .playing
            case .waitingToPlayAtSpecifiedRate:
                event = .waiting
            case .paused:
                event = .waiting
            @unknown default:
                event = nil
            }
            guard let event else { return }
            Task { @MainActor [weak self] in
                self?.eventHandler?(attemptID, event)
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
                as? Error
            let failure = Self.classify(error)
            Task { @MainActor [weak self] in
                self?.eventHandler?(attemptID, .failed(failure))
            }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.eventHandler?(attemptID, .waiting)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.eventHandler?(attemptID, .failed(.transient))
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        clearCurrentItem()
    }

    private func clearCurrentItem() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
        }
        stallObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private nonisolated static func classify(_ error: Error?) -> PlaybackEngineFailure {
        guard let error else { return .unknown }
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet:
                // Only the path monitor owns the public Offline state. A player-item
                // error can race a path update, so keep it in the retryable bucket.
                return .transient
            case .badURL, .unsupportedURL:
                return .unsupportedOrInvalidSource
            default:
                return .transient
            }
        }

        if nsError.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: nsError.code) {
            case .fileFormatNotRecognized, .decoderNotFound, .contentIsNotAuthorized:
                return .unsupportedOrInvalidSource
            default:
                return .transient
            }
        }

        return .unknown
    }
}

@MainActor
final class TaskPlaybackDeadlineScheduler: PlaybackDeadlineScheduling {
    private var task: Task<Void, Never>?

    func schedule(
        _ deadline: PlaybackDeadline,
        handler: @escaping (PlaybackDeadlineID) -> Void
    ) {
        cancel()
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: deadline.duration)
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.task = nil
            handler(deadline.id)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

@MainActor
final class NWPathConnectivitySource: PlaybackConnectivitySourcing {
    var handler: ((PlaybackConnectivity) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.github.ukeSJTU.CodeRadio.connectivity")
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connectivity: PlaybackConnectivity
            switch path.status {
            case .satisfied:
                connectivity = .available
            case .unsatisfied:
                connectivity = .unavailable
            case .requiresConnection:
                connectivity = .unknown
            @unknown default:
                connectivity = .unknown
            }
            Task { @MainActor [weak self] in
                self?.handler?(connectivity)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.cancel()
        handler = nil
    }
}

@MainActor
final class WorkspaceSleepWakeSource: PlaybackSleepWakeSourcing {
    var sleepHandler: (() -> Void)?
    var wakeHandler: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sleepHandler?() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.wakeHandler?() }
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        sleepHandler = nil
        wakeHandler = nil
    }
}

@MainActor
final class UserDefaultsPlaybackPreferences: PlaybackPreferenceStoring {
    private static let qualityKey = "CodeRadio.quality"
    private let defaults: UserDefaults

    var preferredQuality: StreamQuality {
        get {
            let saved = defaults.string(forKey: Self.qualityKey)
            return StreamQuality(rawValue: saved ?? "") ?? .high
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.qualityKey)
        }
    }

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
}
