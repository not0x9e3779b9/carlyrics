import Foundation

public enum LyricPrivacy: String, Codable, Sendable {
    case showLyrics, hideLyrics
}

/// Bounded presentation data shared with a future remote-update service and ActivityKit adapter.
/// Keep artwork and the full lyric document outside an activity's combined 4 KB payload.
public struct LiveActivityViewState: Codable, Equatable, Sendable {
    public let trackTitle: String
    public let artist: String
    public let previousLine: String
    public let currentLine: String
    public let nextLine: String
    public let position: TimeInterval
    public let isPlaying: Bool
    public let hasLyrics: Bool
    public let updatedAt: Date

    public init(track: TrackMetadata?, frame: LyricFrame, updatedAt: Date = Date(), privacy: LyricPrivacy = .showLyrics) {
        trackTitle = Self.clipped(track?.title ?? "No track", to: 64)
        artist = Self.clipped(track?.artist ?? "", to: 64)
        let visible = privacy == .showLyrics
        previousLine = visible ? Self.clipped(frame.previous?.text ?? "", to: 128) : ""
        let display: String
        if let current = frame.current?.text {
            display = current.isEmpty ? "Instrumental" : current
        } else {
            display = frame.hasLyrics ? "Waiting for the first line" : "No lyrics imported"
        }
        currentLine = visible ? Self.clipped(display, to: 128) : "Lyrics hidden"
        nextLine = visible ? Self.clipped(frame.next?.text ?? "", to: 128) : ""
        position = frame.position.isFinite ? max(0, frame.position) : 0
        isPlaying = frame.isPlaying
        hasLyrics = frame.hasLyrics
        self.updatedAt = updatedAt
    }

    private static func clipped(_ text: String, to byteLimit: Int) -> String {
        // Bound UTF-8 bytes rather than characters: emoji and combining marks can be very large.
        let normalized = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard normalized.utf8.count > byteLimit else { return normalized }
        var result = ""
        for character in normalized {
            let candidate = result + String(character)
            guard candidate.utf8.count <= byteLimit - 3 else { break }
            result = candidate
        }
        return result + "…"
    }
}
