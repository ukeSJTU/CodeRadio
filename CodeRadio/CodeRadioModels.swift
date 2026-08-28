import Foundation

enum StreamQuality: String, CaseIterable, Identifiable, Sendable {
    case high
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "128 kbps"
        case .low: "64 kbps"
        }
    }

    var fallbackURL: URL {
        switch self {
        case .high:
            URL(string: "https://coderadio-admin-v2.freecodecamp.org/listen/coderadio/radio.mp3")!
        case .low:
            URL(string: "https://coderadio-admin-v2.freecodecamp.org/listen/coderadio/low.mp3")!
        }
    }
}

enum StationMetadataState: Equatable, Sendable {
    case idle
    case fresh
    case stale
    case unavailable
}

nonisolated struct CodeRadioResponse: Decodable, Sendable {
    let station: Station?
    let listeners: ListenerCount?
    let nowPlaying: NowPlaying?
    let songHistory: [SongHistoryEntry]?
    let isOnline: Bool?

    private enum CodingKeys: String, CodingKey {
        case station, listeners, nowPlaying, songHistory, isOnline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decodedRecognizedSection = false
        station = Self.decodeRecognizedSection(
            Station.self,
            forKey: .station,
            from: container,
            decodedAny: &decodedRecognizedSection
        )
        listeners = Self.decodeRecognizedSection(
            ListenerCount.self,
            forKey: .listeners,
            from: container,
            decodedAny: &decodedRecognizedSection
        )
        nowPlaying = Self.decodeRecognizedSection(
            NowPlaying.self,
            forKey: .nowPlaying,
            from: container,
            decodedAny: &decodedRecognizedSection
        )
        let decodedHistory = Self.decodeRecognizedSection(
            [LossyDecodable<SongHistoryEntry>].self,
            forKey: .songHistory,
            from: container,
            decodedAny: &decodedRecognizedSection
        )
        songHistory = decodedHistory?.compactMap(\.value)
        isOnline = Self.decodeRecognizedSection(
            Bool.self,
            forKey: .isOnline,
            from: container,
            decodedAny: &decodedRecognizedSection
        )

        guard decodedRecognizedSection else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "No recognized station metadata section was usable."
            ))
        }
    }

    private static func decodeRecognizedSection<Value: Decodable>(
        _ type: Value.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>,
        decodedAny: inout Bool
    ) -> Value? {
        guard container.contains(key) else { return nil }
        do {
            guard let value = try container.decodeIfPresent(type, forKey: key) else {
                return nil
            }
            decodedAny = true
            return value
        } catch {
            return nil
        }
    }
}

nonisolated struct Station: Decodable, Sendable {
    let mounts: [StreamMount]

    private enum CodingKeys: String, CodingKey {
        case mounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMounts = try? container.decodeIfPresent(
            [LossyDecodable<StreamMount>].self,
            forKey: .mounts
        )
        mounts = decodedMounts?.compactMap(\.value) ?? []
    }
}

nonisolated struct StreamMount: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let url: URL
    let bitrate: Int
}

nonisolated struct ListenerCount: Decodable, Sendable {
    let current: Int?

    private enum CodingKeys: String, CodingKey {
        case current
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try? container.decodeIfPresent(Int.self, forKey: .current)
        current = decoded.flatMap { $0 >= 0 ? $0 : nil }
    }
}

nonisolated struct NowPlaying: Decodable, Sendable {
    let playedAt: TimeInterval?
    let duration: TimeInterval?
    let song: Song?

    private enum CodingKeys: String, CodingKey {
        case playedAt, duration, song
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPlayedAt = try? container.decodeIfPresent(
            TimeInterval.self,
            forKey: .playedAt
        )
        playedAt = decodedPlayedAt.flatMap { $0 > 0 ? $0 : nil }
        let decodedDuration = try? container.decodeIfPresent(
            TimeInterval.self,
            forKey: .duration
        )
        duration = decodedDuration.flatMap { $0 > 0 ? $0 : nil }
        song = try? container.decodeIfPresent(Song.self, forKey: .song)
    }
}

nonisolated struct SongHistoryEntry: Decodable, Sendable {
    let playedAt: TimeInterval?
    let song: Song?

    private enum CodingKeys: String, CodingKey {
        case playedAt, song
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playedAt = try? container.decodeIfPresent(TimeInterval.self, forKey: .playedAt)
        song = try? container.decodeIfPresent(Song.self, forKey: .song)
    }
}

nonisolated struct Song: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let art: URL?

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, art
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title))
            ?? String(localized: "Unknown title")
        artist = (try? container.decodeIfPresent(String.self, forKey: .artist))
            ?? String(localized: "Unknown artist")
        album = (try? container.decodeIfPresent(String.self, forKey: .album)) ?? ""
        art = try? container.decodeIfPresent(URL.self, forKey: .art)
        id = (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? "\(artist)|\(title)|\(album)"
    }
}

extension JSONDecoder {
    static let codeRadio: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private nonisolated struct LossyDecodable<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
