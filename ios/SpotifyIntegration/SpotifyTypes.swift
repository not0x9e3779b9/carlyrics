import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LyricsCore

public struct SpotifyConfiguration: Sendable, Equatable {
    public let clientID: String
    public let redirectURI: URL

    public init(clientID: String, redirectURI: URL) {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    func validate() throws {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clientID.contains("$("), !clientID.contains("YOUR_"),
              let components = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false),
              let scheme = components.scheme, !scheme.isEmpty,
              components.fragment == nil, components.user == nil, components.password == nil,
              !(components.queryItems ?? []).contains(where: {
                  ["code", "state", "error", "error_description"].contains($0.name)
              }) else { throw SpotifyFailure.invalidConfiguration }
        if scheme.lowercased() == "http" {
            guard ["127.0.0.1", "[::1]", "::1"].contains(components.host ?? "") else {
                throw SpotifyFailure.invalidConfiguration
            }
        }
    }
}

public enum SpotifyFailure: Error, Equatable, Sendable, LocalizedError {
    case invalidConfiguration
    case invalidCallback
    case stateMismatch
    case authorizationCancelled
    case authorizationDenied
    case requiresAuthorization
    case credentialsRevoked
    case invalidResponse
    case networkUnavailable
    case requestCancelled
    case storageUnavailable
    case serviceUnavailable(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval)
    case backingOff(retryAfter: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Complete the Spotify client ID and exact redirect URI configuration."
        case .invalidCallback: return "Spotify returned an unexpected authorization callback."
        case .stateMismatch: return "The authorization callback could not be verified. Please connect again."
        case .authorizationCancelled: return "Spotify authorization was cancelled."
        case .authorizationDenied: return "Spotify denied this request. Check account access and app permissions."
        case .requiresAuthorization, .credentialsRevoked: return "Connect your Spotify account again."
        case .invalidResponse: return "Spotify returned an unsupported response."
        case .networkUnavailable: return "Spotify is unavailable. Check the network connection."
        case .requestCancelled: return "The request was cancelled."
        case .storageUnavailable: return "Secure credential storage is unavailable."
        case .serviceUnavailable(let status): return "Spotify could not complete the request (HTTP \(status))."
        case .rateLimited(let seconds): return "Spotify requested a pause. Try again in \(Self.delayDescription(seconds)) seconds."
        case .backingOff(let seconds): return "Waiting to reconnect. Try again in \(Self.delayDescription(seconds)) seconds."
        }
    }

    private static func delayDescription(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "several" }
        return String(format: "%.0f", ceil(max(0, seconds)))
    }
}

public struct SpotifyCredentials: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Apple applications must supply a Keychain-backed implementation.
public protocol TokenStore: Sendable {
    func load() async throws -> SpotifyCredentials?
    func save(_ credentials: SpotifyCredentials) async throws
    func delete() async throws
}

public enum SpotifyAuthState: Equatable, Sendable {
    case disconnected
    case authorizing
    case connected(expiresAt: Date)
    case refreshing
    case requiresAuthorization
    case failed(SpotifyFailure)
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func retryDelay(now: Date) -> TimeInterval {
        guard let value = header("Retry-After") else { return 30 }
        if let seconds = TimeInterval(value), seconds.isFinite { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(1, formatter.date(from: value)?.timeIntervalSince(now) ?? 30)
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SpotifyFailure.invalidResponse }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            guard let key = $1.key as? String else { return }
            $0[key] = String(describing: $1.value)
        }
        return HTTPResponse(data: data, statusCode: response.statusCode, headers: headers)
    }
}

func sanitizedFailure(_ error: Error) -> SpotifyFailure {
    if let failure = error as? SpotifyFailure { return failure }
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return .requestCancelled }
    return .networkUnavailable
}

func isUsableBearerToken(_ token: String) -> Bool {
    !token.isEmpty && token.utf8.allSatisfy { $0 > 32 && $0 < 127 }
}

public protocol PlaybackStateClient: Sendable {
    func playbackState() async throws -> PlaybackSnapshot
}
