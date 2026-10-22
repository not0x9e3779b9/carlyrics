import ActivityKit
import Foundation

/// Kept in both targets so the app and widget agree on the ActivityKit payload.
/// Credentials, complete lyric documents, and artwork data never belong here.
public struct CarLyricsActivityAttributes: ActivityAttributes {
    public enum PlaybackStatus: String, Codable, Hashable, Sendable {
        case playing
        case paused
        case stale
        case unavailable
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var artist: String
        public var currentLine: String?
        public var previousLine: String?
        public var nextLine: String?
        public var playbackStatus: PlaybackStatus
        public var privacyMode: Bool
        public var isDemo: Bool

        public init(
            title: String,
            artist: String,
            currentLine: String? = nil,
            previousLine: String? = nil,
            nextLine: String? = nil,
            playbackStatus: PlaybackStatus = .playing,
            privacyMode: Bool = false,
            isDemo: Bool = false
        ) {
            self.title = title
            self.artist = artist
            self.currentLine = currentLine
            self.previousLine = previousLine
            self.nextLine = nextLine
            self.playbackStatus = playbackStatus
            self.privacyMode = privacyMode
            self.isDemo = isDemo
        }

        /// Remove private content before transport, in addition to view redaction.
        public var privacyFiltered: Self {
            guard privacyMode else { return self }
            var result = self
            result.title = ""
            result.artist = ""
            result.previousLine = nil
            result.currentLine = nil
            result.nextLine = nil
            return result
        }
    }

    public var sessionID: UUID
    public var startedAt: Date

    public init(sessionID: UUID = UUID(), startedAt: Date = Date()) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }
}
