import Foundation

/// Implement this boundary for a future licensed provider without coupling it to playback APIs.
public protocol LyricsProvider: Sendable {
    func lyrics(for track: TrackMetadata) async throws -> LyricsDocument?
}

/// Explicit track IDs prevent a similarly titled recording from receiving the wrong timing.
/// The application persists imported documents in its private library and restores this registry.
public actor LocalLRCProvider: LyricsProvider {
    private var documents: [String: LyricsDocument]
    private let parser: LRCParser

    public init(documents: [String: LyricsDocument] = [:], parser: LRCParser = .init()) {
        self.documents = documents
        self.parser = parser
    }

    @discardableResult
    public func importLyrics(_ text: String, for trackID: String) -> LyricsDocument {
        let document = parser.parse(text)
        documents[trackID] = document
        return document
    }

    @discardableResult
    public func importFile(at url: URL, for trackID: String) throws -> LyricsDocument {
        let source = try String(contentsOf: url, encoding: .utf8)
        return importLyrics(source, for: trackID)
    }

    public func register(_ document: LyricsDocument, for trackID: String) {
        documents[trackID] = document
    }

    public func removeLyrics(for trackID: String) {
        documents.removeValue(forKey: trackID)
    }

    public func lyrics(for track: TrackMetadata) async throws -> LyricsDocument? {
        documents[track.id]
    }
}

public struct MockLyricsProvider: LyricsProvider {
    public let documents: [String: LyricsDocument]
    public let fallback: LyricsDocument?

    public init(documents: [String: LyricsDocument] = [:], fallback: LyricsDocument? = nil) {
        self.documents = documents
        self.fallback = fallback
    }

    public func lyrics(for track: TrackMetadata) async throws -> LyricsDocument? {
        documents[track.id] ?? fallback
    }
}

public enum SyntheticLyrics {
    public static let demoTrack = TrackMetadata(
        id: "demo:lantern-road", title: "Lantern Road", artist: "CarLyrics Demo", album: "Original Samples", duration: 72
    )

    public static let demoLRC = """
    [ti:Lantern Road]
    [ar:CarLyrics Demo]
    [al:Original Samples]
    [00:03.00]Paper lanterns trace the morning
    [00:12.00]Every window holds a little sky
    [00:21.00]Quiet wheels roll past the garden
    [00:30.00]
    [00:39.00]Clouds make maps across the distance
    [00:48.00]We can watch the colors pass us by
    [01:00.00]Home is where the lanterns shine
    """

    public static let demoDocument = LRCParser().parse(demoLRC)
}
