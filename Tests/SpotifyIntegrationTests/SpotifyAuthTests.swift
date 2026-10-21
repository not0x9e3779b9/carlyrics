import XCTest
import Foundation
@testable import SpotifyIntegration

final class SpotifyAuthTests: XCTestCase, @unchecked Sendable {
    func testAuthorizationUsesPKCEAndOnlyPlaybackStateScope() async throws {
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore())
        let url = try await auth.beginAuthorization()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(query["scope"], "user-read-playback-state")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["redirect_uri"], testConfiguration.redirectURI.absoluteString)
        XCTAssertNil(query["client_secret"])
        let state = await auth.state
        XCTAssertEqual(state, .authorizing)
        await auth.cancelAuthorization()
        let cancelled = await auth.state
        XCTAssertEqual(cancelled, .disconnected)
    }

    func testSuccessfulAuthorizationExchangesCodeAndPersistsCredentials() async throws {
        let expected = generatedCredentials()
        let transport = StubTransport([.response(try tokenResponse(for: expected))])
        let store = MemoryTokenStore()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: transport, now: { testDate })
        let url = try await auth.beginAuthorization()
        try await auth.completeAuthorization(callbackURL: callback(for: url, code: "a+b&=value"))
        let stored = await store.value
        XCTAssertEqual(stored, expected)
        let state = await auth.state
        XCTAssertEqual(state, .connected(expiresAt: expected.expiresAt))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("code=a%2Bb%26%3Dvalue"))
        XCTAssertTrue(body.contains("code_verifier="))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testCallbackRequiresExactRedirectAndMatchingState() async throws {
        for badURL in ["carlyrics://different-callback?code=x&state=wrong",
                       "carlyrics://spotify-callback/extra?code=x&state=wrong",
                       "carlyrics://spotify-callback?code=x&state=wrong#fragment"] {
            let transport = StubTransport([])
            let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(), transport: transport)
            _ = try await auth.beginAuthorization()
            do {
                try await auth.completeAuthorization(callbackURL: URL(string: badURL)!)
                XCTFail("Unexpected callback was accepted")
            } catch { XCTAssertEqual(error as? SpotifyFailure, .invalidCallback) }
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
        let transport = StubTransport([])
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(), transport: transport)
        _ = try await auth.beginAuthorization()
        do {
            try await auth.completeAuthorization(callbackURL: URL(string: "carlyrics://spotify-callback?code=x&state=wrong")!)
            XCTFail("Mismatched state was accepted")
        } catch { XCTAssertEqual(error as? SpotifyFailure, .stateMismatch) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCallbackRejectsDuplicateStateAndCannotBeReplayed() async throws {
        let expected = generatedCredentials()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(),
                                      transport: StubTransport([.response(try tokenResponse(for: expected))]), now: { testDate })
        let url = try await auth.beginAuthorization()
        let valid = callback(for: url)
        var duplicate = URLComponents(url: valid, resolvingAgainstBaseURL: false)!
        duplicate.queryItems!.append(URLQueryItem(name: "state", value: "duplicate"))
        do {
            try await auth.completeAuthorization(callbackURL: duplicate.url!)
            XCTFail("Duplicate state was accepted")
        } catch { XCTAssertEqual(error as? SpotifyFailure, .stateMismatch) }
        do {
            try await auth.completeAuthorization(callbackURL: valid)
            XCTFail("Consumed authorization was accepted")
        } catch { XCTAssertEqual(error as? SpotifyFailure, .invalidCallback) }
    }

    func testDeniedAuthorizationAndCancelledTransaction() async throws {
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore())
        let url = try await auth.beginAuthorization()
        var denied = URLComponents(url: callback(for: url), resolvingAgainstBaseURL: false)!
        denied.queryItems = denied.queryItems!.filter { $0.name != "code" } + [URLQueryItem(name: "error", value: "access_denied")]
        do {
            try await auth.completeAuthorization(callbackURL: denied.url!)
            XCTFail("Authorization denial was ignored")
        } catch { XCTAssertEqual(error as? SpotifyFailure, .authorizationDenied) }
        let failedState = await auth.state
        XCTAssertEqual(failedState, .failed(.authorizationDenied))
        let newURL = try await auth.beginAuthorization()
        await auth.cancelAuthorization()
        do {
            try await auth.completeAuthorization(callbackURL: callback(for: newURL))
            XCTFail("Cancelled transaction was accepted")
        } catch { XCTAssertEqual(error as? SpotifyFailure, .invalidCallback) }
    }

    func testRestoredCredentialsRemainUsableAfterCancellingAuthorizationWithoutNetwork() async throws {
        let expected = generatedCredentials()
        let transport = StubTransport([])
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(expected), transport: transport, now: { testDate })
        try await auth.restore()
        _ = try await auth.beginAuthorization()
        await auth.cancelAuthorization()
        let actual = try await auth.validAccessToken()
        XCTAssertEqual(actual, expected.accessToken)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testRefreshRetainsExistingRefreshTokenWhenResponseOmitsIt() async throws {
        let old = generatedCredentials(expiresAt: testDate.addingTimeInterval(-1))
        let replacement = generatedCredentials()
        let store = MemoryTokenStore(old)
        let transport = StubTransport([.response(try tokenResponse(for: replacement, includeRefresh: false))])
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: transport, now: { testDate })
        try await auth.restore()
        let stored = await store.value
        XCTAssertEqual(stored?.accessToken, replacement.accessToken)
        XCTAssertEqual(stored?.refreshToken, old.refreshToken)
        let requests = await transport.requests
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("client_id=development-client"))
    }

    func testSuspendedRestoreCannotAuthorizePlaybackWithPreviousCredentials() async throws {
        let oldCredentials = generatedCredentials()
        let replacement = generatedCredentials()
        let store = SuspendedLoadTokenStore(oldCredentials)
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, now: { testDate })
        try await auth.restore()
        let previousAuthorization = try await auth.playbackAuthorization()
        await store.suspendNextLoad(replacement: replacement)
        let restoring = Task { try await auth.restore() }
        await store.waitForLoad()
        do { _ = try await auth.playbackAuthorization(); XCTFail("Previous credentials were usable during restoration") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .requiresAuthorization) }
        do { try await auth.requirePlaybackRevision(previousAuthorization.revision); XCTFail("Previous session revision survived restoration") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .requestCancelled) }
        await store.releaseLoad()
        try await restoring.value
        let restoredAuthorization = try await auth.playbackAuthorization()
        XCTAssertEqual(restoredAuthorization.token, replacement.accessToken)
        XCTAssertNotEqual(restoredAuthorization.revision, previousAuthorization.revision)
    }

    func testConcurrentRefreshIsCoalescedAndReplacementRefreshTokenIsPersisted() async throws {
        let old = generatedCredentials()
        let replacement = generatedCredentials()
        let store = MemoryTokenStore(old)
        let transport = ControlledTransport()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: transport, now: { testDate })
        try await auth.restore()
        let first = Task { try await auth.validAccessToken(forceRefresh: true) }
        await transport.waitUntilStarted()
        let second = Task { try await auth.validAccessToken() }
        await transport.release(try tokenResponse(for: replacement))
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, replacement.accessToken)
        XCTAssertEqual(secondValue, replacement.accessToken)
        let count = await transport.requestCount
        XCTAssertEqual(count, 1)
        let stored = await store.value
        XCTAssertEqual(stored, replacement)
        let saves = await store.saveCount
        XCTAssertEqual(saves, 1)
    }

    func testRevokedRefreshClearsStoredCredentialsAndRequiresAuthorization() async throws {
        let old = generatedCredentials(expiresAt: testDate.addingTimeInterval(-1))
        let store = MemoryTokenStore(old)
        let response = HTTPResponse(data: Data(#"{"error":"invalid_grant","error_description":"private response details"}"#.utf8), statusCode: 400)
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: StubTransport([.response(response)]), now: { testDate })
        do {
            try await auth.restore()
            XCTFail("Revoked credentials were accepted")
        } catch {
            XCTAssertEqual(error as? SpotifyFailure, .credentialsRevoked)
            XCTAssertFalse(error.localizedDescription.contains("private response details"))
        }
        let stored = await store.value
        XCTAssertNil(stored)
        let state = await auth.state
        XCTAssertEqual(state, .requiresAuthorization)
        let hasCredentials = await auth.hasCredentials
        XCTAssertFalse(hasCredentials)
    }

    func testDisconnectDuringRefreshDoesNotRestoreCredentials() async throws {
        let store = MemoryTokenStore(generatedCredentials())
        let transport = ControlledTransport()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: transport, now: { testDate })
        try await auth.restore()
        let refresh = Task { try await auth.validAccessToken(forceRefresh: true) }
        await transport.waitUntilStarted()
        try await auth.disconnect()
        await transport.release(try tokenResponse(for: generatedCredentials()))
        do { _ = try await refresh.value; XCTFail("Disconnected refresh returned credentials") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .requestCancelled) }
        let stored = await store.value
        XCTAssertNil(stored)
        let state = await auth.state
        XCTAssertEqual(state, .disconnected)
    }

    func testTokenRefreshRespectsRateLimitBeforeAnotherNetworkRequest() async throws {
        let clock = MutableClock(testDate)
        let store = MemoryTokenStore(generatedCredentials())
        let transport = StubTransport([
            .response(HTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "60"])),
            .response(try tokenResponse(for: generatedCredentials()))
        ])
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store, transport: transport, now: { clock.now() })
        try await auth.restore()
        do { _ = try await auth.validAccessToken(forceRefresh: true); XCTFail("Token rate limit was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .rateLimited(retryAfter: 60)) }
        let hasCredentials = await auth.hasCredentials
        XCTAssertTrue(hasCredentials)
        clock.advance(10)
        do { _ = try await auth.validAccessToken(forceRefresh: true); XCTFail("Token cooldown was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .rateLimited(retryAfter: 50)) }
        let before = await transport.requests
        XCTAssertEqual(before.count, 1)
        clock.advance(50)
        _ = try await auth.validAccessToken(forceRefresh: true)
        let after = await transport.requests
        XCTAssertEqual(after.count, 2)
    }

    func testStorageAndNetworkFailuresAreSanitized() async throws {
        let store = MemoryTokenStore()
        await store.failStorage()
        let auth = SpotifyAuthManager(configuration: testConfiguration, store: store)
        do { try await auth.restore(); XCTFail("Storage failure was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .storageUnavailable) }

        let offline = SpotifyAuthManager(configuration: testConfiguration, store: MemoryTokenStore(), transport: StubTransport([.networkError]))
        let url = try await offline.beginAuthorization()
        do { try await offline.completeAuthorization(callbackURL: callback(for: url)); XCTFail("Network failure was ignored") }
        catch { XCTAssertEqual(error as? SpotifyFailure, .networkUnavailable) }
    }

    func testInvalidConfigurationFailsBeforeAuthorization() async throws {
        for config in [SpotifyConfiguration(clientID: "", redirectURI: testConfiguration.redirectURI),
                       SpotifyConfiguration(clientID: "development-client", redirectURI: URL(string: "http://localhost/callback")!),
                       SpotifyConfiguration(clientID: "development-client", redirectURI: URL(string: "carlyrics://callback#fragment")!)] {
            let auth = SpotifyAuthManager(configuration: config, store: MemoryTokenStore())
            do { _ = try await auth.beginAuthorization(); XCTFail("Invalid configuration was accepted") }
            catch { XCTAssertEqual(error as? SpotifyFailure, .invalidConfiguration) }
        }
    }
}
