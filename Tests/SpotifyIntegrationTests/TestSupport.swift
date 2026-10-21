import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SpotifyIntegration

actor MemoryTokenStore: TokenStore {
    private(set) var value: SpotifyCredentials?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    var shouldFail = false

    init(_ value: SpotifyCredentials? = nil) { self.value = value }

    func load() throws -> SpotifyCredentials? {
        if shouldFail { throw SpotifyFailure.storageUnavailable }
        return value
    }

    func save(_ credentials: SpotifyCredentials) throws {
        if shouldFail { throw SpotifyFailure.storageUnavailable }
        value = credentials
        saveCount += 1
    }

    func delete() throws {
        if shouldFail { throw SpotifyFailure.storageUnavailable }
        value = nil
        deleteCount += 1
    }

    func failStorage() { shouldFail = true }
}

actor StubTransport: HTTPTransport {
    enum Step: Sendable {
        case response(HTTPResponse)
        case networkError
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw SpotifyFailure.invalidResponse }
        switch steps.removeFirst() {
        case .response(let response): return response
        case .networkError: throw URLError(.notConnectedToInternet)
        }
    }
}

/// Keeps a network request suspended until a test explicitly releases its response.
actor ControlledTransport: HTTPTransport {
    private var responseContinuation: CheckedContinuation<HTTPResponse, Error>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var releasedResponse: HTTPResponse?
    private(set) var requestCount = 0

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        if let releasedResponse { return releasedResponse }
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuation = continuation
            for waiter in startContinuations { waiter.resume() }
            startContinuations.removeAll()
        }
    }

    func waitUntilStarted() async {
        if responseContinuation != nil { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func release(_ response: HTTPResponse) {
        releasedResponse = response
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
    }
}

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(seconds)
    }
}

let testDate = Date(timeIntervalSince1970: 1_700_000_000)
let testConfiguration = SpotifyConfiguration(clientID: "development-client", redirectURI: URL(string: "carlyrics://spotify-callback")!)

func generatedCredentials(expiresAt: Date = testDate.addingTimeInterval(3_600)) -> SpotifyCredentials {
    SpotifyCredentials(accessToken: UUID().uuidString, refreshToken: UUID().uuidString, expiresAt: expiresAt)
}

func tokenResponse(for credentials: SpotifyCredentials, includeRefresh: Bool = true) throws -> HTTPResponse {
    var body: [String: Any] = ["access_token": credentials.accessToken, "token_type": "Bearer", "expires_in": 3_600]
    if includeRefresh { body["refresh_token"] = credentials.refreshToken }
    return HTTPResponse(data: try JSONSerialization.data(withJSONObject: body), statusCode: 200)
}

func callback(for authorizationURL: URL, code: String = "ephemeral-code") -> URL {
    let query = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
    let state = query.first { $0.name == "state" }!.value!
    var components = URLComponents(url: testConfiguration.redirectURI, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "state", value: state)]
    return components.url!
}

func playbackJSON(overrides: [String: Any] = [:]) throws -> Data {
    var body: [String: Any] = [
        "device": ["is_active": true], "is_playing": true, "progress_ms": 12_345,
        "currently_playing_type": "track",
        "item": ["id": "synthetic-track", "name": "Evening Circuit", "type": "track", "is_local": false,
                 "duration_ms": 180_000, "artists": [["name": "Signal Ensemble"], ["name": "Guest Signal"]],
                 "album": ["name": "Test Frequencies", "images": [["url": "https://example.com/art.png"]]],
                 "external_urls": ["spotify": "https://open.spotify.com/track/synthetic-track"]]
    ]
    for (key, value) in overrides { body[key] = value }
    return try JSONSerialization.data(withJSONObject: body)
}
