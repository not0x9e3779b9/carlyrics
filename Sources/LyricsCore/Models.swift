import Foundation

public struct TrackMetadata: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: URL?
    public let spotifyURL: URL?

    public init(id: String, title: String, artist: String, album: String = "", duration: TimeInterval,
                artworkURL: URL? = nil, spotifyURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.artworkURL = artworkURL
        self.spotifyURL = spotifyURL
    }
}

public enum PlaybackAvailability: String, Codable, Equatable, Sendable {
    case available, noActiveDevice, noContent, advertisement, episode, unsupported, offline
}

public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    public let track: TrackMetadata?
    public let position: TimeInterval
    public let isPlaying: Bool
    public let observedAt: Date
    public let availability: PlaybackAvailability

    public init(track: TrackMetadata?, position: TimeInterval, isPlaying: Bool,
                observedAt: Date = Date(), availability: PlaybackAvailability = .available) {
        self.track = track
        self.position = position.isFinite ? max(0, position) : 0
        self.isPlaying = isPlaying
        self.observedAt = observedAt
        self.availability = availability
    }

    /// Uses the local observation time as an anchor; no network requests are needed between samples.
    public func estimatedPosition(at date: Date) -> TimeInterval {
        let advances = isPlaying && availability == .available && track != nil
        let elapsed = advances ? max(0, date.timeIntervalSince(observedAt)) : 0
        let estimated = position + elapsed
        guard let duration = track?.duration, duration > 0 else { return estimated }
        return min(duration, estimated)
    }
}

public struct TimedLyricLine: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let timestamp: TimeInterval
    public let text: String

    public init(timestamp: TimeInterval, text: String, id: Int = 0) {
        self.id = id
        self.timestamp = timestamp.isFinite ? max(0, timestamp) : 0
        self.text = text
    }
}

public struct LyricsMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var author: String?
    public var offsetMilliseconds: Int
    public var additional: [String: String]

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, author: String? = nil,
                offsetMilliseconds: Int = 0, additional: [String: String] = [:]) {
        self.title = title
        self.artist = artist
        self.album = album
        self.author = author
        self.offsetMilliseconds = offsetMilliseconds
        self.additional = additional
    }
}

public struct LRCWarning: Codable, Equatable, Sendable {
    public let lineNumber: Int
    public let message: String

    public init(lineNumber: Int, message: String) {
        self.lineNumber = lineNumber
        self.message = message
    }
}

public struct LyricsDocument: Codable, Equatable, Sendable {
    public let lines: [TimedLyricLine]
    public let metadata: LyricsMetadata
    public let warnings: [LRCWarning]

    /// Normalizes ordering even when documents come from another provider.
    public init(lines: [TimedLyricLine], metadata: LyricsMetadata = .init(), warnings: [LRCWarning] = []) {
        self.lines = lines.enumerated()
            .sorted { left, right in
                left.element.timestamp == right.element.timestamp
                    ? left.offset < right.offset : left.element.timestamp < right.element.timestamp
            }
            .enumerated()
            .map { index, entry in
                TimedLyricLine(timestamp: entry.element.timestamp, text: entry.element.text, id: index)
            }
        self.metadata = metadata
        self.warnings = warnings
    }
}
