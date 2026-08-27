import Foundation

struct StreamURLResolver {
    func url(for quality: StreamQuality, mounts: [StreamMount]) -> URL {
        let sortedMounts = mounts.sorted { $0.bitrate < $1.bitrate }
        switch quality {
        case .high:
            return sortedMounts.last?.url ?? quality.fallbackURL
        case .low:
            return sortedMounts.first?.url ?? quality.fallbackURL
        }
    }
}
