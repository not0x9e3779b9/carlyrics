import Foundation
import XCTest
@testable import LyricsCore

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date = date.addingTimeInterval(seconds)
    }
}

final class SynchronizationEngineTests: XCTestCase {
    private let track = TrackMetadata(id: "test:a", title: "Window Garden", artist: "Sample Ensemble", duration: 60)
    private let document = LRCParser().parse("[00:05]A seed\n[00:10]A stem\n[00:15]\n[00:20]A flower")

    private func engine(clock: TestClock, position: TimeInterval, isPlaying: Bool = false) -> SynchronizationEngine {
        var engine = SynchronizationEngine(now: { clock.now() })
        engine.update(snapshot: .init(track: track, position: position, isPlaying: isPlaying, observedAt: clock.now()), lyrics: document)
        return engine
    }

    func testBeforeFirstLyricHasOnlyNextLine() {
        let frame = engine(clock: TestClock(), position: 0).frame()
        XCTAssertNil(frame.current)
        XCTAssertNil(frame.previous)
        XCTAssertEqual(frame.next?.text, "A seed")
        XCTAssertTrue(frame.hasLyrics)
    }

    func testExactBoundaryAndNearbyLines() {
        let frame = engine(clock: TestClock(), position: 10).frame()
        XCTAssertEqual(frame.previous?.text, "A seed")
        XCTAssertEqual(frame.current?.text, "A stem")
        XCTAssertEqual(frame.next?.text, "")
    }

    func testBetweenBoundaries() {
        XCTAssertEqual(engine(clock: TestClock(), position: 9.999).frame().current?.text, "A seed")
    }

    func testAfterFinalLine() {
        let frame = engine(clock: TestClock(), position: 45).frame()
        XCTAssertEqual(frame.current?.text, "A flower")
        XCTAssertNil(frame.next)
    }

    func testInstrumentalGapIsEmptyCurrentLine() {
        let frame = engine(clock: TestClock(), position: 18).frame()
        XCTAssertEqual(frame.current?.text, "")
        XCTAssertEqual(frame.next?.text, "A flower")
    }

    func testLocalClockAdvancesBetweenSnapshots() {
        let clock = TestClock()
        let engine = engine(clock: clock, position: 8, isPlaying: true)
        clock.advance(3)
        XCTAssertEqual(engine.frame().position, 11)
        XCTAssertEqual(engine.frame().current?.text, "A stem")
    }

    func testPauseFreezesAndResumeContinuesClock() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 8, isPlaying: true)
        clock.advance(1)
        engine.pause()
        clock.advance(20)
        XCTAssertEqual(engine.frame().position, 9)
        XCTAssertFalse(engine.frame().isPlaying)
        engine.resume()
        clock.advance(2)
        XCTAssertEqual(engine.frame().position, 11)
        XCTAssertTrue(engine.frame().isPlaying)
    }

    func testPausedSpotifySnapshotDoesNotAdvance() {
        let clock = TestClock()
        let engine = engine(clock: clock, position: 7)
        clock.advance(30)
        XCTAssertEqual(engine.frame().position, 7)
    }

    func testSeekBackwardAndForward() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 12)
        engine.seek(to: 6)
        XCTAssertEqual(engine.frame().current?.text, "A seed")
        engine.seek(to: 22)
        XCTAssertEqual(engine.frame().current?.text, "A flower")
        engine.seek(to: -100)
        XCTAssertEqual(engine.frame().position, 0)
    }

    func testTrackChangeClearsPreviousLyrics() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 12)
        let nextTrack = TrackMetadata(id: "test:b", title: "Paper Lantern", artist: "Sample Ensemble", duration: 80)
        engine.apply(snapshot: .init(track: nextTrack, position: 0, isPlaying: true, observedAt: clock.now()))
        XCTAssertFalse(engine.frame().hasLyrics)
        XCTAssertNil(engine.frame().current)
        XCTAssertEqual(engine.currentTrack?.id, nextTrack.id)
    }

    func testNoTrackClearsLyricsAndStopsEstimate() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 12, isPlaying: true)
        engine.apply(snapshot: .init(track: nil, position: 0, isPlaying: false, observedAt: clock.now(), availability: .noContent))
        clock.advance(10)
        XCTAssertEqual(engine.frame().position, 0)
        XCTAssertFalse(engine.frame().hasLyrics)
    }

    func testFreshSnapshotCorrectsPlaybackDrift() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 6, isPlaying: true)
        clock.advance(10)
        XCTAssertEqual(engine.frame().position, 16)
        engine.apply(snapshot: .init(track: track, position: 9, isPlaying: true, observedAt: clock.now()))
        XCTAssertEqual(engine.frame().position, 9)
        XCTAssertEqual(engine.frame().current?.text, "A seed")
        clock.advance(2)
        XCTAssertEqual(engine.frame().position, 11)
    }

    func testPositiveAndNegativeUserTimingOffsets() {
        var engine = engine(clock: TestClock(), position: 9)
        engine.userTimingOffset = 1
        XCTAssertEqual(engine.frame().current?.text, "A stem")
        XCTAssertEqual(engine.frame().position, 9)
        engine.userTimingOffset = -5
        XCTAssertNil(engine.frame().current)
        engine.userTimingOffset = .nan
        XCTAssertEqual(engine.frame().current?.text, "A seed")
    }

    func testFinalDuplicateWinsAtExactBoundary() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 5)
        engine.setLyrics(LRCParser().parse("[00:05]First\n[00:05]Second\n[00:10]Third"))
        XCTAssertEqual(engine.frame().current?.text, "Second")
        XCTAssertEqual(engine.frame().previous?.text, "First")
        XCTAssertEqual(engine.frame().next?.text, "Third")
    }

    func testClockIsClampedToDurationAndDoesNotRunBackward() {
        let clock = TestClock()
        let engine = engine(clock: clock, position: 58, isPlaying: true)
        clock.advance(10)
        XCTAssertEqual(engine.frame().position, 60)
        clock.advance(-20)
        XCTAssertEqual(engine.frame().position, 58)
    }

    func testUnavailablePlaybackDoesNotAdvance() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 5)
        engine.apply(snapshot: .init(track: track, position: 7, isPlaying: true, observedAt: clock.now(), availability: .offline))
        clock.advance(20)
        XCTAssertEqual(engine.frame().position, 7)
        XCTAssertFalse(engine.frame().isPlaying)
    }

    func testResetRemovesPlaybackAndLyrics() {
        var engine = engine(clock: TestClock(), position: 10)
        engine.reset()
        XCTAssertEqual(engine.frame().position, 0)
        XCTAssertNil(engine.frame().current)
        XCTAssertFalse(engine.frame().hasLyrics)
        XCTAssertNil(engine.currentTrack)
    }

    func testLargeDocumentBinarySearchFindsExactBoundary() {
        let clock = TestClock()
        var engine = engine(clock: clock, position: 42)
        engine.setLyrics(.init(lines: (0..<10_000).map { .init(timestamp: Double($0) / 100, text: "Marker \($0)") }))
        XCTAssertEqual(engine.frame().current?.text, "Marker 4200")
    }
}
