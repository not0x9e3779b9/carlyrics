import Foundation
import XCTest
@testable import LyricsCore

final class ProviderAndPresentationTests: XCTestCase, @unchecked Sendable {
    func testLocalImportUsesExactTrackBinding() async throws {
        let provider = LocalLRCProvider()
        let track = SyntheticLyrics.demoTrack
        let imported = await provider.importLyrics("[00:01]A clockwork cloud", for: track.id)
        let found = try await provider.lyrics(for: track)
        XCTAssertEqual(found, imported)
        let other = TrackMetadata(id: "different", title: track.title, artist: track.artist, duration: 20)
        let missing = try await provider.lyrics(for: other)
        XCTAssertNil(missing)
        await provider.removeLyrics(for: track.id)
        let removed = try await provider.lyrics(for: track)
        XCTAssertNil(removed)
    }

    func testLocalProviderReadsUTF8LRCFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("lrc")
        try "[00:01]작은 정원".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = LocalLRCProvider()
        let document = try await provider.importFile(at: url, for: "local:one")
        XCTAssertEqual(document.lines.first?.text, "작은 정원")
    }

    func testLocalProviderReportsFileFailure() async {
        let provider = LocalLRCProvider()
        do {
            _ = try await provider.importFile(at: URL(fileURLWithPath: "/missing-\(UUID().uuidString).lrc"), for: "none")
            XCTFail("A missing file must throw.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testMockProviderSupportsFoundMissingAndFallback() async throws {
        let track = SyntheticLyrics.demoTrack
        let known = MockLyricsProvider(documents: [track.id: SyntheticLyrics.demoDocument])
        let found = try await known.lyrics(for: track)
        XCTAssertEqual(found, SyntheticLyrics.demoDocument)
        let missing = try await MockLyricsProvider().lyrics(for: track)
        XCTAssertNil(missing)
        let fallback = try await MockLyricsProvider(fallback: SyntheticLyrics.demoDocument).lyrics(for: track)
        XCTAssertEqual(fallback, found)
    }

    private func frame(text: String = "A small lantern", previous: String = "A paper map", next: String = "A quiet garden") -> LyricFrame {
        .init(position: 10, lyricPosition: 10, previous: .init(timestamp: 5, text: previous),
              current: .init(timestamp: 10, text: text), next: .init(timestamp: 15, text: next),
              isPlaying: true, hasLyrics: true)
    }

    func testViewStateContainsGlanceableNearbyLines() {
        let state = LiveActivityViewState(track: SyntheticLyrics.demoTrack, frame: frame())
        XCTAssertEqual(state.trackTitle, SyntheticLyrics.demoTrack.title)
        XCTAssertEqual(state.currentLine, "A small lantern")
        XCTAssertEqual(state.previousLine, "A paper map")
        XCTAssertEqual(state.nextLine, "A quiet garden")
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.hasLyrics)
    }

    func testViewStateHidesLyricsForPrivacy() {
        let state = LiveActivityViewState(track: SyntheticLyrics.demoTrack, frame: frame(), privacy: .hideLyrics)
        XCTAssertEqual(state.currentLine, "Lyrics hidden")
        XCTAssertEqual(state.previousLine, "")
        XCTAssertEqual(state.nextLine, "")
    }

    func testViewStateLabelsInstrumentalGap() {
        let state = LiveActivityViewState(track: SyntheticLyrics.demoTrack, frame: frame(text: ""))
        XCTAssertEqual(state.currentLine, "Instrumental")
    }

    func testViewStateLabelsMissingLyrics() {
        let missing = LyricFrame(position: 0, lyricPosition: 0, previous: nil, current: nil, next: nil, isPlaying: false, hasLyrics: false)
        let state = LiveActivityViewState(track: nil, frame: missing)
        XCTAssertEqual(state.currentLine, "No lyrics imported")
        XCTAssertEqual(state.trackTitle, "No track")
    }

    func testViewStateClipsUnicodeByUTF8Bytes() throws {
        let longText = String(repeating: "🌱", count: 1_000)
        let track = TrackMetadata(id: "sample", title: longText, artist: longText, duration: 60)
        let state = LiveActivityViewState(track: track, frame: frame(text: longText, previous: longText, next: longText))
        XCTAssertLessThanOrEqual(state.trackTitle.utf8.count, 64)
        XCTAssertLessThanOrEqual(state.currentLine.utf8.count, 128)
        XCTAssertTrue(state.currentLine.hasSuffix("…"))
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 1_500)
    }

    func testWorstCaseJSONEscapingLeavesPayloadSpaceForAttributes() throws {
        let controls = String(repeating: "\u{0001}", count: 2_000)
        let track = TrackMetadata(id: "sample", title: controls, artist: controls, duration: 60)
        let state = LiveActivityViewState(track: track, frame: frame(text: controls, previous: controls, next: controls))
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 3_500)
    }

    func testPresentationNormalizesWhitespaceAndRoundTripsCodable() throws {
        let state = LiveActivityViewState(track: SyntheticLyrics.demoTrack, frame: frame(text: "  Paper\n  lanterns\tshine  "))
        XCTAssertEqual(state.currentLine, "Paper lanterns shine")
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LiveActivityViewState.self, from: encoded), state)
    }

    func testModelsRoundTripWithoutPlatformFrameworks() throws {
        let original = PlaybackSnapshot(track: SyntheticLyrics.demoTrack, position: 12.5, isPlaying: true, availability: .available)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSnapshot.self, from: JSONEncoder().encode(original)), original)
        XCTAssertEqual(try JSONDecoder().decode(LyricsDocument.self, from: JSONEncoder().encode(SyntheticLyrics.demoDocument)), SyntheticLyrics.demoDocument)
    }
}
