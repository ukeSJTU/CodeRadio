import Foundation

enum StreamQuality: String, CaseIterable, Identifiable {
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

struct CodeRadioResponse: Decodable {
    let station: Station
    let listeners: ListenerCount
    let nowPlaying: NowPlaying
    let songHistory: [SongHistoryEntry]
    let isOnline: Bool
}

struct Station: Decodable {
    let mounts: [StreamMount]
}

struct StreamMount: Decodable, Identifiable {
    let id: Int
    let name: String
    let url: URL
    let bitrate: Int
}

struct ListenerCount: Decodable {
    let current: Int
}

struct NowPlaying: Decodable {
    let playedAt: TimeInterval
    let duration: TimeInterval
    let song: Song
}

struct SongHistoryEntry: Decodable {
    let playedAt: TimeInterval
    let song: Song
}

struct Song: Decodable, Identifiable, Equatable {
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
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown title"
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? "Unknown artist"
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        art = try container.decodeIfPresent(URL.self, forKey: .art)
        id = try container.decodeIfPresent(String.self, forKey: .id)
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
