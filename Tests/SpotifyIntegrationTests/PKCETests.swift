import XCTest
@testable import SpotifyIntegration

final class PKCETests: XCTestCase {
    func testChallengeMatchesRFC7636Vector() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testSHA256EmptyInputAndMultipleBlockVectors() {
        XCTAssertEqual(PKCE.challenge(for: ""), "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU")
        XCTAssertEqual(PKCE.challenge(for: String(repeating: "a", count: 64)),
                       "_-BU_nrgy23GXDr5th1SCfQ5hR20PQulmXM33xVGaOs")
    }

    func testGeneratedVerifierAndStateUseURLSafeRandomMaterial() {
        let values = (0..<12).map { _ in PKCE() }
        XCTAssertEqual(Set(values.map(\.verifier)).count, values.count)
        for value in values {
            XCTAssertTrue((43...128).contains(value.verifier.count))
            XCTAssertEqual(value.verifier.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression), value.verifier.startIndex..<value.verifier.endIndex)
            XCTAssertEqual(value.challenge.count, 43)
            XCTAssertEqual(value.challenge, PKCE.challenge(for: value.verifier))
        }
        let states = (0..<12).map { _ in PKCE.randomState() }
        XCTAssertEqual(Set(states).count, states.count)
        XCTAssertTrue(states.allSatisfy { $0.count == 43 })
    }
}
