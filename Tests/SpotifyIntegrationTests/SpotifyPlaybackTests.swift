import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LyricsCore
@testable import SpotifyIntegration

final class SpotifyPlaybackTests: XCTestCase, @unchecked Sendable {
    func testDecodingTrackMetadataAndMilliseconds() throws {
        let snapshot = try SpotifyPlaybackResponse.decode(playbackJSON(), observedAt: testDate)
        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.track?.id, "synthetic-track")
        XCTAssertEqual(snapshot.track?.title, "Evening Circuit")
        XCTAssertEqual(snapshot.track?.artist, "Signal Ensemble, Guest Signal")
        XCTAssertEqual(snapshot.track?.album, "Test Frequencies")
        XCTAssertEqual(snapshot.track?.duration, 180)
        XCTAssertEqual(snapshot.track?.artworkURL?.absoluteString, "https://example.com/art.png")
        XCTAssertEqual(snapshot.track?.spotifyURL?.host, "open.spotify.com")
        XCTAssertEqual(snapshot.position, 12.345, accuracy: 0.0001)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.observedAt, testDate)
    }

    func testMissingAndNullPlaybackFieldsAreSafe() throws {
        let empty = try SpotifyPlaybackResponse.decode(Data("{}".utf8))
        XCTAssertEqual(empty.availability, .noActiveDevice)
        let nullItem = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["item": NSNull()]))
        XCTAssertEqual(nullItem.availability, .noContent)
        let nullProgress = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["progress_ms": NSNull(), "is_playing": NSNull()]))
        XCTAssertEqual(nullProgress.position, 0)
        XCTAssertFalse(nullProgress.isPlaying)
        let noDevice = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["device": NSNull()]))
        XCTAssertEqual(noDevice.availability, .noActiveDevice)
        let inactiveDevice = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["device": ["is_active": false]]))
        XCTAssertEqual(inactiveDevice.availability, .noActiveDevice)
    }

    func testAdvertisementsEpisodesUnknownAndLocalTracksAreUnsupported() throws {
        for (kind, expected) in [("ad", PlaybackAvailability.advertisement), ("episode", .episode), ("unknown", .unsupported)] {
            let snapshot = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["currently_playing_type": kind]))
            XCTAssertEqual(snapshot.availability, expected)
            XCTAssertNil(snapshot.track)
            XCTAssertFalse(snapshot.isPlaying)
        }
        let local = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["item": ["is_local": true]]))
        XCTAssertEqual(local.availability, .unsupported)
        let missingIdentity = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["item": ["name": "Unknown recording"]]))
        XCTAssertEqual(missingIdentity.availability, .unsupported)
    }

    func testMissingAlbumImagesAndLinksDoNotDiscardValidTrack() throws {
        let item: [String: Any] = ["id": "minimal", "name": "Minimal Signal", "duration_ms": 60_000,
                                  "artists": [["name": "Test Artist"]]]
        let snapshot = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["item": item]))
        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.track?.album, "")
        XCTAssertNil(snapshot.track?.artworkURL)
        XCTAssertNil(snapshot.track?.spotifyURL)
    }

    func testProgressIsClampedAndMalformedJSONIsSanitized() throws {
        let negative = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["progress_ms": -1_000]))
        XCTAssertEqual(negative.position, 0)
        let afterEnd = try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["progress_ms": 9_999_999]))
        XCTAssertEqual(afterEnd.position, 180)
        XCTAssertThrowsError(try SpotifyPlaybackResponse.decode(Data("not JSON".utf8))) {
            XCTAssertEqual($0 as? SpotifyFailure, .invalidResponse)
        }
        XCTAssertThrowsError(try SpotifyPlaybackResponse.decode(playbackJSON(overrides: ["progress_ms": "wrong-type"]))) {
            XCTAssertEqual($0 as? SpotifyFailure, .invalidResponse)
        }
    }

    func testProductionClientSendsOnlyReadRequestAndMapsNoContent() async throws {
        let credentials = generatedCredentials()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(credentials), now: { testDate })
        try await auth.restore()
        let transport = StubTransport([.response(HTTPResponse(data: Data(), statusCode: 204))])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { testDate })
        let snapshot = try await client.playbackState()
        XCTAssertEqual(snapshot.availability, .noActiveDevice)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.spotify.com/v1/me/player")
        XCTAssertTrue(requests[0].httpMethod == nil || requests[0].httpMethod == "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(credentials.accessToken)")
        XCTAssertNil(requests[0].httpBody)
    }

    func testUnauthorizedPlaybackRefreshesAndRetriesExactlyOnce() async throws {
        let replacement = generatedCredentials()
        let tokenTransport = StubTransport([.response(try tokenResponse(for: replacement))])
        let store = MemoryTokenStore(generatedCredentials())
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: tokenTransport, now: { testDate })
        try await auth.restore()
        let transport = StubTransport([
            .response(HTTPResponse(data: Data(), statusCode: 401)),
            .response(HTTPResponse(data: try playbackJSON(), statusCode: 200))
        ])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { testDate })
        let snapshot = try await client.playbackState()
        XCTAssertEqual(snapshot.track?.id, "synthetic-track")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer \(replacement.accessToken)")
        let refreshRequests = await tokenTransport.requests
        XCTAssertEqual(refreshRequests.count, 1)
    }

    func testRepeatedUnauthorizedPlaybackClearsCredentialsWithoutThirdRequest() async throws {
        let store = MemoryTokenStore(generatedCredentials())
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store,
                                      transport: StubTransport([.response(try tokenResponse(for: generatedCredentials()))]), now: { testDate })
        try await auth.restore()
        let transport = StubTransport([
            .response(HTTPResponse(data: Data(), statusCode: 401)), .response(HTTPResponse(data: Data(), statusCode: 401))
        ])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { testDate })
        do { _ = try await client.playbackState(); XCTFail("Rejected credentials were accepted") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .credentialsRevoked) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let stored = await store.value
        XCTAssertNil(stored)
        let state = await auth.state
        XCTAssertEqual(state, .requiresAuthorization)
    }

    func testRateLimitHonorsRetryAfterWithoutEarlyNetworkRequests() async throws {
        let clock = MutableClock(testDate)
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(generatedCredentials()), now: { clock.now() })
        try await auth.restore()
        let transport = StubTransport([
            .response(HTTPResponse(data: Data(), statusCode: 429, headers: ["retry-after": "45"])),
            .response(HTTPResponse(data: try playbackJSON(), statusCode: 200))
        ])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { clock.now() })
        do { _ = try await client.playbackState(); XCTFail("Rate limit was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .rateLimited(retryAfter: 45)) }
        clock.advance(10)
        do { _ = try await client.playbackState(); XCTFail("Rate-limit cooldown was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .rateLimited(retryAfter: 35)) }
        let before = await transport.requests
        XCTAssertEqual(before.count, 1)
        clock.advance(35)
        let snapshot = try await client.playbackState()
        XCTAssertEqual(snapshot.availability, .available)
        let after = await transport.requests
        XCTAssertEqual(after.count, 2)
    }

    func testRetryAfterHTTPDateAndMissingHeaderFallback() {
        let response = HTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "Tue, 14 Nov 2023 22:14:20 GMT"])
        XCTAssertEqual(response.retryDelay(now: testDate), 60)
        XCTAssertEqual(HTTPResponse(data: Data(), statusCode: 429).retryDelay(now: testDate), 30)
        XCTAssertEqual(HTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "not-a-date"]).retryDelay(now: testDate), 30)
    }

    func testOfflineAndServerErrorsUseExponentialBackoffThenRecover() async throws {
        let clock = MutableClock(testDate)
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(generatedCredentials()), now: { clock.now() })
        try await auth.restore()
        let transport = StubTransport([
            .networkError, .response(HTTPResponse(data: Data(), statusCode: 503)),
            .response(HTTPResponse(data: try playbackJSON(), statusCode: 200))
        ])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { clock.now() })
        do { _ = try await client.playbackState(); XCTFail("Offline failure was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .networkUnavailable) }
        do { _ = try await client.playbackState(); XCTFail("Network backoff was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .backingOff(retryAfter: 2)) }
        clock.advance(2)
        do { _ = try await client.playbackState(); XCTFail("Service failure was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .serviceUnavailable(statusCode: 503)) }
        do { _ = try await client.playbackState(); XCTFail("Increasing backoff was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .backingOff(retryAfter: 4)) }
        clock.advance(4)
        let recovered = try await client.playbackState()
        XCTAssertEqual(recovered.availability, .available)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testForbiddenPlaybackDoesNotEraseCredentialsOrExposeResponseBody() async throws {
        let store = MemoryTokenStore(generatedCredentials())
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, now: { testDate })
        try await auth.restore()
        let transport = StubTransport([.response(HTTPResponse(data: Data("private service details".utf8), statusCode: 403))])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { testDate })
        do { _ = try await client.playbackState(); XCTFail("Forbidden request was accepted") }
        catch {
            XCTAssertEqual(error as? SpotifyFailure, .authorizationDenied)
            XCTAssertFalse(error.localizedDescription.contains("private service details"))
        }
        let stored = await store.value
        XCTAssertNotNil(stored)
    }

    func testExpiredCredentialsRefreshBeforeReadingPlayback() async throws {
        let clock = MutableClock(testDate)
        let replacement = generatedCredentials(expiresAt: testDate.addingTimeInterval(7_200))
        let tokenTransport = StubTransport([.response(try tokenResponse(for: replacement))])
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(generatedCredentials()),
                                      transport: tokenTransport, now: { clock.now() })
        try await auth.restore()
        clock.advance(3_600)
        let transport = StubTransport([.response(HTTPResponse(data: try playbackJSON(), statusCode: 200))])
        let client = SpotifyPlaybackClient(authentication: auth, transport: transport, now: { clock.now() })
        let snapshot = try await client.playbackState()
        XCTAssertEqual(snapshot.availability, .available)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(replacement.accessToken)")
        let refreshRequests = await tokenTransport.requests
        XCTAssertEqual(refreshRequests.count, 1)
    }

    func testMockClientAdvancesFixturesAndCanPresentFailure() async throws {
        let first = PlaybackSnapshot(track: nil, position: 0, isPlaying: false, observedAt: testDate, availability: .noContent)
        let second = try SpotifyPlaybackResponse.decode(playbackJSON(), observedAt: testDate)
        let client = MockSpotifyPlaybackClient(snapshots: [first, second])
        let actualFirst = try await client.playbackState()
        let actualSecond = try await client.playbackState()
        let repeated = try await client.playbackState()
        XCTAssertEqual(actualFirst, first)
        XCTAssertEqual(actualSecond, second)
        XCTAssertEqual(repeated, second)
        await client.setFailure(.networkUnavailable)
        do { _ = try await client.playbackState(); XCTFail("Mock failure was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .networkUnavailable) }
    }
}
