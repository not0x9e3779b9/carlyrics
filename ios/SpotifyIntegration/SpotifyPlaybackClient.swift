import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LyricsCore

public struct SpotifyPlaybackResponse: Decodable, Sendable {
    private struct Device: Decodable, Sendable {
        let isActive: Bool?
        enum CodingKeys: String, CodingKey { case isActive = "is_active" }
    }

    private struct Artist: Decodable, Sendable { let name: String? }
    private struct Image: Decodable, Sendable { let url: String? }
    private struct Links: Decodable, Sendable { let spotify: String? }
    private struct Album: Decodable, Sendable {
        let name: String?
        let images: [Image]?
    }

    private struct Item: Decodable, Sendable {
        let id: String?
        let name: String?
        let artists: [Artist]?
        let album: Album?
        let durationMS: TimeInterval?
        let isLocal: Bool?
        let type: String?
        let externalURLs: Links?

        enum CodingKeys: String, CodingKey {
            case id, name, artists, album, type
            case durationMS = "duration_ms", isLocal = "is_local", externalURLs = "external_urls"
        }
    }

    private let device: Device?
    private let item: Item?
    private let isPlaying: Bool?
    private let progressMS: TimeInterval?
    private let contentType: String?

    enum CodingKeys: String, CodingKey {
        case device, item
        case isPlaying = "is_playing", progressMS = "progress_ms", contentType = "currently_playing_type"
    }

    public static func decode(_ data: Data, observedAt: Date = Date()) throws -> PlaybackSnapshot {
        do { return try JSONDecoder().decode(Self.self, from: data).snapshot(observedAt: observedAt) }
        catch { throw SpotifyFailure.invalidResponse }
    }

    public func snapshot(observedAt: Date = Date()) -> PlaybackSnapshot {
        func unavailable(_ reason: PlaybackAvailability) -> PlaybackSnapshot {
            PlaybackSnapshot(track: nil, position: 0, isPlaying: false, observedAt: observedAt, availability: reason)
        }
        switch contentType ?? item?.type {
        case "ad": return unavailable(.advertisement)
        case "episode": return unavailable(.episode)
        case nil, "track": break
        default: return unavailable(.unsupported)
        }
        guard let device, device.isActive != false else { return unavailable(.noActiveDevice) }
        guard let item else { return unavailable(.noContent) }
        guard item.isLocal != true, item.type == nil || item.type == "track",
              let identifier = item.id, !identifier.isEmpty,
              let title = item.name, !title.isEmpty,
              let durationMS = item.durationMS, durationMS.isFinite, durationMS > 0,
              let artists = item.artists?.compactMap(\.name).filter({ !$0.isEmpty }), !artists.isEmpty else {
            return unavailable(.unsupported)
        }
        let duration = durationMS / 1_000
        let positionMS = progressMS.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let track = TrackMetadata(id: identifier, title: title, artist: artists.joined(separator: ", "),
                                  album: item.album?.name ?? "", duration: duration,
                                  artworkURL: item.album?.images?.compactMap { Self.webURL($0.url) }.first,
                                  spotifyURL: Self.webURL(item.externalURLs?.spotify))
        return PlaybackSnapshot(track: track, position: min(duration, max(0, positionMS / 1_000)),
                                isPlaying: isPlaying ?? false, observedAt: observedAt)
    }

    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// Reads metadata only. Connecting Spotify playback to timed lyrics requires separate policy approval.
public actor SpotifyPlaybackClient: PlaybackStateClient {
    private let authentication: SpotifyAuthManager
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var nextRequestAt: Date?
    private var rateLimited = false
    private var transientFailureCount = 0
    private var inFlight: Task<PlaybackSnapshot, Error>?

    public init(authentication: SpotifyAuthManager, transport: any HTTPTransport = URLSessionTransport(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.authentication = authentication
        self.transport = transport
        self.now = now
    }

    public func playbackState() async throws -> PlaybackSnapshot {
        if let inFlight { return try await inFlight.value }
        if let nextRequestAt, nextRequestAt > now() {
            let delay = nextRequestAt.timeIntervalSince(now())
            throw rateLimited ? SpotifyFailure.rateLimited(retryAfter: delay) : SpotifyFailure.backingOff(retryAfter: delay)
        }
        let task = Task { try await self.fetchPlayback() }
        inFlight = task
        return try await task.value
    }

    private func fetchPlayback() async throws -> PlaybackSnapshot {
        defer { inFlight = nil }
        do {
            var token = try await authentication.validAccessToken()
            var response = try await requestPlayback(token: token)
            if response.statusCode == 401 {
                token = try await authentication.validAccessToken(forceRefresh: true)
                response = try await requestPlayback(token: token)
                if response.statusCode == 401 {
                    try await authentication.invalidateCredentials()
                    throw SpotifyFailure.credentialsRevoked
                }
            }
            if response.statusCode == 429 {
                let delay = response.retryDelay(now: now())
                nextRequestAt = now().addingTimeInterval(delay)
                rateLimited = true
                throw SpotifyFailure.rateLimited(retryAfter: delay)
            }
            if response.statusCode == 403 { throw SpotifyFailure.authorizationDenied }
            guard (200..<300).contains(response.statusCode) else {
                throw SpotifyFailure.serviceUnavailable(statusCode: response.statusCode)
            }
            let result: PlaybackSnapshot
            if response.statusCode == 204 {
                result = PlaybackSnapshot(track: nil, position: 0, isPlaying: false,
                                          observedAt: now(), availability: .noActiveDevice)
            } else {
                result = try SpotifyPlaybackResponse.decode(response.data, observedAt: now())
            }
            transientFailureCount = 0
            nextRequestAt = nil
            rateLimited = false
            return result
        } catch {
            let failure = sanitizedFailure(error)
            switch failure {
            case .networkUnavailable, .serviceUnavailable(statusCode: 500...599):
                transientFailureCount = min(transientFailureCount + 1, 6)
                nextRequestAt = now().addingTimeInterval(min(60, pow(2, Double(transientFailureCount))))
                rateLimited = false
            case .rateLimited(let delay):
                // This also respects rate limiting returned by the token refresh endpoint.
                nextRequestAt = now().addingTimeInterval(delay)
                rateLimited = true
            default: break
            }
            throw failure
        }
    }

    private func requestPlayback(token: String) async throws -> HTTPResponse {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do { return try await transport.send(request) }
        catch { throw sanitizedFailure(error) }
    }
}

public actor MockSpotifyPlaybackClient: PlaybackStateClient {
    private var snapshots: [PlaybackSnapshot]
    private var index = 0
    private var failure: SpotifyFailure?

    public init(snapshots: [PlaybackSnapshot] = [], failure: SpotifyFailure? = nil) {
        self.snapshots = snapshots
        self.failure = failure
    }

    public func playbackState() async throws -> PlaybackSnapshot {
        if let failure { throw failure }
        guard !snapshots.isEmpty else {
            return PlaybackSnapshot(track: nil, position: 0, isPlaying: false, availability: .noContent)
        }
        let result = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return result
    }

    public func setSnapshots(_ values: [PlaybackSnapshot]) {
        snapshots = values
        index = 0
    }

    public func setFailure(_ value: SpotifyFailure?) { failure = value }
}
