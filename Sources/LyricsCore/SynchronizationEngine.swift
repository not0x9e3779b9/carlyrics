import Foundation

public struct LyricFrame: Codable, Equatable, Sendable {
    public let position: TimeInterval
    public let lyricPosition: TimeInterval
    public let previous: TimedLyricLine?
    public let current: TimedLyricLine?
    public let next: TimedLyricLine?
    public let isPlaying: Bool
    public let hasLyrics: Bool

    public init(position: TimeInterval, lyricPosition: TimeInterval, previous: TimedLyricLine?,
                current: TimedLyricLine?, next: TimedLyricLine?, isPlaying: Bool, hasLyrics: Bool) {
        self.position = position
        self.lyricPosition = lyricPosition
        self.previous = previous
        self.current = current
        self.next = next
        self.isPlaying = isPlaying
        self.hasLyrics = hasLyrics
    }
}

/// Own one engine on a serial owner (such as the application view model).
public struct SynchronizationEngine: Sendable {
    private let now: @Sendable () -> Date
    private var snapshot: PlaybackSnapshot?
    private var lyrics: LyricsDocument?

    /// Positive values show lyrics earlier; negative values delay them.
    public var userTimingOffset: TimeInterval

    public init(now: @escaping @Sendable () -> Date = { Date() }, userTimingOffset: TimeInterval = 0) {
        self.now = now
        self.userTimingOffset = userTimingOffset
    }

    public var currentTrack: TrackMetadata? { snapshot?.track }

    /// A new sample replaces the playback anchor and immediately corrects drift or seeks.
    public mutating func apply(snapshot incoming: PlaybackSnapshot) {
        if let snapshot, snapshot.track?.id != incoming.track?.id {
            lyrics = nil
        }
        snapshot = incoming
    }

    public mutating func setLyrics(_ document: LyricsDocument?) {
        lyrics = document
    }

    public mutating func update(snapshot: PlaybackSnapshot, lyrics: LyricsDocument?) {
        apply(snapshot: snapshot)
        setLyrics(lyrics)
    }

    public mutating func pause() {
        reanchor(position: snapshot?.estimatedPosition(at: now()) ?? 0, isPlaying: false)
    }

    public mutating func resume() {
        reanchor(position: snapshot?.estimatedPosition(at: now()) ?? 0, isPlaying: true)
    }

    public mutating func seek(to position: TimeInterval) {
        reanchor(position: position, isPlaying: snapshot?.isPlaying ?? false)
    }

    public mutating func reset() {
        snapshot = nil
        lyrics = nil
    }

    public func frame() -> LyricFrame {
        let position = snapshot?.estimatedPosition(at: now()) ?? 0
        let offset = userTimingOffset.isFinite ? userTimingOffset : 0
        let lyricPosition = position + offset
        let lines = lyrics?.lines ?? []
        // Upper bound selects the final duplicate at an exact timestamp deterministically.
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lines[middle].timestamp <= lyricPosition {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let active = lower - 1
        return LyricFrame(
            position: position,
            lyricPosition: lyricPosition,
            previous: active > 0 ? lines[active - 1] : nil,
            current: active >= 0 ? lines[active] : nil,
            next: lower < lines.count ? lines[lower] : nil,
            isPlaying: snapshot?.isPlaying == true && snapshot?.availability == .available && snapshot?.track != nil,
            hasLyrics: !lines.isEmpty
        )
    }

    private mutating func reanchor(position: TimeInterval, isPlaying: Bool) {
        guard let snapshot else { return }
        self.snapshot = PlaybackSnapshot(track: snapshot.track, position: position, isPlaying: isPlaying,
                                         observedAt: now(), availability: snapshot.availability)
    }
}
