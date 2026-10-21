import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor SpotifyAuthManager {
    public private(set) var state: SpotifyAuthState = .disconnected
    /// A transient network or rate-limit failure does not discard the saved session.
    public var hasCredentials: Bool { credentials != nil }

    private struct Authorization: Sendable {
        let state: String
        let verifier: String
    }

    private let configuration: SpotifyConfiguration
    private let store: any TokenStore
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var credentials: SpotifyCredentials?
    private var authorization: Authorization?
    private var refreshTask: Task<SpotifyCredentials, Error>?
    private var storageTask: Task<Void, Error>?
    private var generation = 0
    private var nextTokenRequestAt: Date?
    private var tokenRateLimited = false
    private var tokenFailureCount = 0

    public init(configuration: SpotifyConfiguration, store: any TokenStore,
                transport: any HTTPTransport = URLSessionTransport(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.store = store
        self.transport = transport
        self.now = now
    }

    public func restore() async throws {
        try configuration.validate()
        invalidatePendingRequests()
        let expectedGeneration = generation
        if let storageTask { _ = try? await storageTask.value }
        let stored: SpotifyCredentials?
        do { stored = try await store.load() }
        catch { throw record(.storageUnavailable) }
        guard generation == expectedGeneration else { throw SpotifyFailure.requestCancelled }
        guard let stored, isUsableBearerToken(stored.accessToken), !stored.refreshToken.isEmpty,
              stored.expiresAt.timeIntervalSince1970.isFinite else {
            credentials = nil
            state = .disconnected
            return
        }
        credentials = stored
        state = .connected(expiresAt: stored.expiresAt)
        if stored.expiresAt.timeIntervalSince(now()) <= 30 { _ = try await validAccessToken() }
    }

    /// Starts one in-memory authorization transaction. A new attempt invalidates the previous state.
    public func beginAuthorization() throws -> URL {
        try configuration.validate()
        invalidatePendingRequests()
        let pkce = PKCE()
        let stateValue = PKCE.randomState()
        authorization = Authorization(state: stateValue, verifier: pkce.verifier)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: "user-read-playback-state"),
            URLQueryItem(name: "state", value: stateValue),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge)
        ]
        guard let url = components.url else { throw record(.invalidConfiguration) }
        state = .authorizing
        return url
    }

    public func completeAuthorization(callbackURL: URL) async throws {
        guard let pending = authorization else { throw SpotifyFailure.invalidCallback }
        authorization = nil
        let expectedGeneration = generation
        do {
            let items = try callbackItems(callbackURL)
            let returnedStates = items.filter { $0.name == "state" }
            guard returnedStates.count == 1, returnedStates[0].value == pending.state else {
                throw SpotifyFailure.stateMismatch
            }
            let errors = items.filter { $0.name == "error" }
            if !errors.isEmpty {
                guard errors.count == 1 else { throw SpotifyFailure.invalidCallback }
                throw errors[0].value == "access_denied"
                    ? SpotifyFailure.authorizationDenied : SpotifyFailure.invalidCallback
            }
            let codes = items.filter { $0.name == "code" }
            guard codes.count == 1, let code = codes[0].value, !code.isEmpty else {
                throw SpotifyFailure.invalidCallback
            }
            try checkTokenBackoff()
            let result = try await Self.requestCredentials(
                configuration: configuration, transport: transport, now: now(),
                parameters: ["grant_type": "authorization_code", "code": code,
                             "redirect_uri": configuration.redirectURI.absoluteString,
                             "code_verifier": pending.verifier], previousRefreshToken: nil)
            guard generation == expectedGeneration else { throw SpotifyFailure.requestCancelled }
            resetTokenBackoff()
            try await persist(result)
            guard generation == expectedGeneration else { throw SpotifyFailure.requestCancelled }
            credentials = result
            state = .connected(expiresAt: result.expiresAt)
        } catch {
            let failure = sanitizedFailure(error)
            if generation == expectedGeneration {
                recordTokenFailure(failure)
                state = .failed(failure)
            }
            throw failure
        }
    }

    public func cancelAuthorization() {
        invalidatePendingRequests()
        state = credentials.map { .connected(expiresAt: $0.expiresAt) } ?? .disconnected
    }

    public func disconnect() async throws {
        invalidatePendingRequests()
        credentials = nil
        state = .disconnected
        do { try await removeStoredCredentials() }
        catch { throw record(.storageUnavailable) }
    }

    public func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        try configuration.validate()
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let current = credentials else {
            state = .requiresAuthorization
            throw SpotifyFailure.requiresAuthorization
        }
        if !forceRefresh && current.expiresAt.timeIntervalSince(now()) > 30 { return current.accessToken }
        try checkTokenBackoff()
        let expectedGeneration = generation
        state = .refreshing
        let task = Task { try await self.refresh(current, generation: expectedGeneration) }
        refreshTask = task
        return try await task.value.accessToken
    }

    /// Called after a refreshed access token is still rejected by the playback endpoint.
    func invalidateCredentials() async throws {
        invalidatePendingRequests()
        credentials = nil
        state = .requiresAuthorization
        do { try await removeStoredCredentials() }
        catch { throw record(.storageUnavailable) }
    }

    private func refresh(_ previous: SpotifyCredentials, generation expectedGeneration: Int) async throws -> SpotifyCredentials {
        do {
            let result = try await Self.requestCredentials(
                configuration: configuration, transport: transport, now: now(),
                parameters: ["grant_type": "refresh_token", "refresh_token": previous.refreshToken],
                previousRefreshToken: previous.refreshToken)
            guard generation == expectedGeneration else { throw SpotifyFailure.requestCancelled }
            resetTokenBackoff()
            try await persist(result)
            guard generation == expectedGeneration else { throw SpotifyFailure.requestCancelled }
            credentials = result
            state = .connected(expiresAt: result.expiresAt)
            refreshTask = nil
            return result
        } catch {
            let failure = sanitizedFailure(error)
            if generation == expectedGeneration {
                refreshTask = nil
                recordTokenFailure(failure)
                if failure == .credentialsRevoked {
                    credentials = nil
                    state = .requiresAuthorization
                    do { try await removeStoredCredentials() }
                    catch { throw record(.storageUnavailable) }
                } else {
                    state = .failed(failure)
                }
            }
            throw failure
        }
    }

    private func invalidatePendingRequests() {
        generation &+= 1
        authorization = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // Queue storage mutations so a completed refresh cannot repopulate storage after disconnect.
    private func persist(_ value: SpotifyCredentials) async throws {
        let previous = storageTask
        let store = self.store
        let operation = Task {
            if let previous { _ = try? await previous.value }
            try await store.save(value)
        }
        storageTask = operation
        do { try await operation.value }
        catch { throw SpotifyFailure.storageUnavailable }
    }

    private func removeStoredCredentials() async throws {
        let previous = storageTask
        let store = self.store
        let operation = Task {
            if let previous { _ = try? await previous.value }
            try await store.delete()
        }
        storageTask = operation
        try await operation.value
    }

    private func record(_ failure: SpotifyFailure) -> SpotifyFailure {
        state = .failed(failure)
        return failure
    }

    private func checkTokenBackoff() throws {
        guard let nextTokenRequestAt, nextTokenRequestAt > now() else { return }
        let delay = nextTokenRequestAt.timeIntervalSince(now())
        throw record(tokenRateLimited ? .rateLimited(retryAfter: delay) : .backingOff(retryAfter: delay))
    }

    private func recordTokenFailure(_ failure: SpotifyFailure) {
        switch failure {
        case .rateLimited(let delay):
            nextTokenRequestAt = now().addingTimeInterval(delay)
            tokenRateLimited = true
        case .networkUnavailable, .serviceUnavailable(statusCode: 500...599):
            tokenFailureCount = min(tokenFailureCount + 1, 6)
            nextTokenRequestAt = now().addingTimeInterval(min(60, pow(2, Double(tokenFailureCount))))
            tokenRateLimited = false
        default: break
        }
    }

    private func resetTokenBackoff() {
        nextTokenRequestAt = nil
        tokenRateLimited = false
        tokenFailureCount = 0
    }

    private func callbackItems(_ url: URL) throws -> [URLQueryItem] {
        guard var actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var expected = URLComponents(url: configuration.redirectURI, resolvingAgainstBaseURL: false),
              actual.fragment == nil else { throw SpotifyFailure.invalidCallback }
        let items = actual.queryItems ?? []
        let expectedItems = expected.queryItems ?? []
        actual.query = nil
        expected.query = nil
        guard actual.url?.absoluteString == expected.url?.absoluteString else {
            throw SpotifyFailure.invalidCallback
        }
        for item in expectedItems {
            guard items.filter({ $0 == item }).count == expectedItems.filter({ $0 == item }).count else {
                throw SpotifyFailure.invalidCallback
            }
        }
        return items
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let tokenType: String
        let expiresIn: TimeInterval
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", tokenType = "token_type"
            case expiresIn = "expires_in", refreshToken = "refresh_token"
        }
    }

    private struct TokenError: Decodable { let error: String }

    private static func requestCredentials(configuration: SpotifyConfiguration, transport: any HTTPTransport,
                                           now: Date, parameters: [String: String],
                                           previousRefreshToken: String?) async throws -> SpotifyCredentials {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var fields = parameters
        fields["client_id"] = configuration.clientID
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        let response: HTTPResponse
        do { response = try await transport.send(request) }
        catch { throw sanitizedFailure(error) }
        if response.statusCode == 429 { throw SpotifyFailure.rateLimited(retryAfter: response.retryDelay(now: now)) }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(TokenError.self, from: response.data)
            if failure?.error == "invalid_grant" || response.statusCode == 401 { throw SpotifyFailure.credentialsRevoked }
            if failure?.error == "invalid_client" { throw SpotifyFailure.invalidConfiguration }
            if response.statusCode == 403 { throw SpotifyFailure.authorizationDenied }
            throw SpotifyFailure.serviceUnavailable(statusCode: response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.data),
              isUsableBearerToken(decoded.accessToken), decoded.tokenType.lowercased() == "bearer",
              decoded.expiresIn.isFinite, decoded.expiresIn > 0,
              let refreshToken = decoded.refreshToken ?? previousRefreshToken, !refreshToken.isEmpty else {
            throw SpotifyFailure.invalidResponse
        }
        return SpotifyCredentials(accessToken: decoded.accessToken, refreshToken: refreshToken,
                                  expiresAt: now.addingTimeInterval(decoded.expiresIn))
    }
}
