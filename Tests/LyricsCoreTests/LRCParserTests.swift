import Foundation
import XCTest
@testable import LyricsCore

final class LRCParserTests: XCTestCase {
    private let parser = LRCParser()

    func testStandardTimestampsAndMinuteValues() {
        let document = parser.parse("[00:03]A silver seed\n[1:05]A tiny tree\n[120:00]A shaded hill")
        XCTAssertEqual(document.lines.map(\.timestamp), [3, 65, 7_200])
        XCTAssertEqual(document.lines.map(\.text), ["A silver seed", "A tiny tree", "A shaded hill"])
        XCTAssertTrue(document.warnings.isEmpty)
    }

    func testTenthsHundredthsAndThousandths() {
        let document = parser.parse("[00:01.5]One\n[00:02.25]Two\n[00:03.125]Three")
        XCTAssertEqual(document.lines[0].timestamp, 1.5, accuracy: 0.00001)
        XCTAssertEqual(document.lines[1].timestamp, 2.25, accuracy: 0.00001)
        XCTAssertEqual(document.lines[2].timestamp, 3.125, accuracy: 0.00001)
    }

    func testMultipleTimestampsExpandIntoSeparateLines() {
        let document = parser.parse("[00:30.00][00:10.00][00:20.00]The paper boats return")
        XCTAssertEqual(document.lines.map(\.timestamp), [10, 20, 30])
        XCTAssertEqual(document.lines.map(\.text), Array(repeating: "The paper boats return", count: 3))
        XCTAssertEqual(document.lines.map(\.id), [0, 1, 2])
    }

    func testMetadataAndUnknownTags() {
        let document = parser.parse("[ti: Window Garden ]\n[ar:Sample Ensemble]\n[al:Small Things]\n[by:Local Author]\n[re:Recorder]\n[00:01]The seed wakes")
        XCTAssertEqual(document.metadata.title, "Window Garden")
        XCTAssertEqual(document.metadata.artist, "Sample Ensemble")
        XCTAssertEqual(document.metadata.album, "Small Things")
        XCTAssertEqual(document.metadata.author, "Local Author")
        XCTAssertEqual(document.metadata.additional["re"], "Recorder")
        XCTAssertTrue(document.warnings.isEmpty)
    }

    func testMetadataIsCaseInsensitiveAndCanContainColons() {
        let document = parser.parse("[TI:Garden: Dawn]\n[AR:River]\n[00:01]A lantern")
        XCTAssertEqual(document.metadata.title, "Garden: Dawn")
        XCTAssertEqual(document.metadata.artist, "River")
    }

    func testPositiveOffsetAppliesGloballyEvenWhenTagFollowsLyrics() {
        let document = parser.parse("[00:01]First light\n[00:02]Second light\n[offset:+250]")
        XCTAssertEqual(document.metadata.offsetMilliseconds, 250)
        XCTAssertEqual(document.lines.map(\.timestamp), [1.25, 2.25])
    }

    func testNegativeOffsetClampsAtZero() {
        let document = parser.parse("[offset:-1500]\n[00:01]First light\n[00:02]Second light")
        XCTAssertEqual(document.lines.map(\.timestamp), [0, 0.5])
    }

    func testLastOffsetWinsWithoutApplyingOffsetsTwice() {
        let document = parser.parse("[offset:500]\n[00:01]A turn\n[offset:-100]")
        XCTAssertEqual(document.lines[0].timestamp, 0.9, accuracy: 0.00001)
    }

    func testInvalidOffsetKeepsLastValidOffsetAndRecovers() {
        let document = parser.parse("[offset:100]\n[offset:soon]\n[00:01]Still a garden")
        XCTAssertEqual(document.lines[0].timestamp, 1.1, accuracy: 0.00001)
        XCTAssertEqual(document.warnings.map(\.lineNumber), [2])
    }

    func testUnicodeAndWhitespaceNormalization() {
        let document = parser.parse("\u{FEFF}[00:01]   작은   빛\t✨   café  \r\n[00:02]  花の道  ")
        XCTAssertEqual(document.lines.map(\.text), ["작은 빛 ✨ café", "花の道"])
    }

    func testBlankLinesAndTimedInstrumentalGap() {
        let document = parser.parse("\n \t\r\n[00:01]A green gate\n[00:03]\n\n[00:08]The gate opens")
        XCTAssertEqual(document.lines.count, 3)
        XCTAssertEqual(document.lines[1].text, "")
        XCTAssertEqual(document.lines[1].timestamp, 3)
        XCTAssertTrue(document.warnings.isEmpty)
    }

    func testMalformedInputRecoversAtNextLineAndValidTimestampOnSameLine() {
        let document = parser.parse("[00:61]Invalid\nwords without time\n[broken][00:03]Recovered\n[00:04]Next\n[00:05")
        XCTAssertEqual(document.lines.map(\.text), ["Recovered", "Next"])
        XCTAssertEqual(document.warnings.map(\.lineNumber), [1, 2, 3, 5])
    }

    func testInvalidFractionAndMinuteFormsAreRejected() {
        let document = parser.parse("[-1:03]A\n[00:01.1234]B\n[00:01.]C\n[xx:02]D\n[00:01.2]Valid")
        XCTAssertEqual(document.lines.map(\.text), ["Valid"])
        XCTAssertGreaterThanOrEqual(document.warnings.count, 3)
    }

    func testEmptyAndWhitespaceOnlyFiles() {
        for text in ["", " \r\n\t\n", "\u{FEFF}"] {
            let document = parser.parse(text)
            XCTAssertTrue(document.lines.isEmpty)
            XCTAssertTrue(document.warnings.isEmpty)
        }
    }

    func testDuplicatesAndOutOfOrderInputKeepStableOrdering() {
        let document = parser.parse("[00:03]Third\n[00:01]First\n[00:02]Second A\n[00:02]Second B")
        XCTAssertEqual(document.lines.map(\.timestamp), [1, 2, 2, 3])
        XCTAssertEqual(document.lines.map(\.text), ["First", "Second A", "Second B", "Third"])
    }

    func testProviderDocumentInitializerSortsAndAssignsDistinctIDs() {
        let document = LyricsDocument(lines: [.init(timestamp: 3, text: "Later"), .init(timestamp: 1, text: "Earlier")])
        XCTAssertEqual(document.lines.map(\.text), ["Earlier", "Later"])
        XCTAssertEqual(Set(document.lines.map(\.id)).count, 2)
    }

    func testBracketedTextAfterLyricsIsPreserved() {
        let document = parser.parse("[00:01]The sign says [welcome]")
        XCTAssertEqual(document.lines[0].text, "The sign says [welcome]")
    }

    func testOriginalDemoFixtureContainsNoWarnings() {
        XCTAssertEqual(SyntheticLyrics.demoDocument.lines.count, 7)
        XCTAssertTrue(SyntheticLyrics.demoDocument.warnings.isEmpty)
    }
}
