import SwiftUI
import AuthenticationServices
import LyricsCore
import SpotifyIntegration

@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case empty, loading, ready, demo, unauthorized, offline, rateLimited, unsupported, noPlayback, error

        var title: String {
            switch self {
            case .empty: return "Your next line starts here"
            case .loading: return "Checking playback"
            case .ready: return "Connected to Spotify"
            case .demo: return "Synthetic rehearsal"
            case .unauthorized: return "Connect your account"
            case .offline: return "You’re offline"
            case .rateLimited: return "Spotify needs a moment"
            case .unsupported: return "This content has no lyric view"
            case .noPlayback: return "Nothing is playing"
            case .error: return "Something needs attention"
            }
        }
    }

    let configuration = AppConfiguration()
    let library = LyricsLibrary()
    let activity = LiveActivityService()
    private let browser = BrowserAuthentication()
    private var authentication: SpotifyAuthManager?
    private var client: SpotifyPlaybackClient?
    private var engine = SynchronizationEngine()
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var foreground = false
    private var bootstrapped = false
    private var lastActivityState: CarLyricsActivityAttributes.ContentState?
    private var lastActivityPublishedAt: Date?
    private var lastPlaybackAt: Date?
    private var hasFreshPlayback = false
    private var playbackGeneration: UInt64 = 0
    private var playbackRequestGeneration: UInt64 = 0
    private var trackGeneration: UInt64 = 0
    private var lyricRequestGeneration: UInt64 = 0
    private var authenticationGeneration: UInt64 = 0

    @Published private(set) var status: Status = .empty
    @Published private(set) var track: TrackMetadata?
    @Published private(set) var frame = SynchronizationEngine().frame()
    @Published private(set) var isConnected = false
    @Published private(set) var isDemo = false
    @Published private(set) var isConnecting = false
    @Published private(set) var documents: [LyricsLibrary.Entry] = []
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var parseWarnings = 0
    @Published var message: String?
    @Published var timingOffset: Double = UserDefaults.standard.double(forKey: "lyricOffset") {
        didSet {
            engine.userTimingOffset = timingOffset
            UserDefaults.standard.set(timingOffset, forKey: "lyricOffset")
            updateFrame()
        }
    }
    @Published var privacyMode = (UserDefaults.standard.object(forKey: "activityPrivacy") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(privacyMode, forKey: "activityPrivacy")
            Task { await publishActivity(force: true) }
        }
    }

    var lyricsAllowed: Bool { isDemo || configuration.allowsSpotifyLyrics }
    var hasLyrics: Bool { frame.hasLyrics }
    var activityIsStale: Bool {
        !foreground || (!isDemo && (!hasFreshPlayback || lastPlaybackAt.map { Date().timeIntervalSince($0) > 15 } != false))
    }

    init() {
        if let config = configuration.spotify {
            let authentication = SpotifyAuthManager(configuration: config, store: KeychainTokenStore())
            self.authentication = authentication
            client = SpotifyPlaybackClient(authentication: authentication)
        }
        engine.userTimingOffset = timingOffset
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        activity.restore()
        do { try await library.restore(); documents = library.entries }
        catch { message = "The saved lyric library could not be loaded. Your original files are unchanged." }
        if let authentication {
            do { try await authentication.restore() }
            catch { record("Stored authorization is unavailable. Reconnect if needed.") }
            await updateAuthenticationState()
        }
        setForeground(foreground)
        record("Application ready. Foreground playback updates only.")
    }

    func setForeground(_ active: Bool) {
        foreground = active
        playbackGeneration &+= 1
        let generation = playbackGeneration
        pollTask?.cancel(); pollTask = nil
        clockTask?.cancel(); clockTask = nil
        guard active else {
            hasFreshPlayback = false
            lastPlaybackAt = nil
            updateFrame()
            lastActivityState = nil
            Task { [weak self] in
                guard let self, !self.foreground, self.playbackGeneration == generation else { return }
                await self.activity.markStale()
            }
            return
        }
        if isConnected && !isDemo {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.refreshPlayback()
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateFrame()
                await self.publishActivity()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    func connect() async {
        guard !isConnecting else { return }
        guard let authentication else {
            message = configuration.issues.joined(separator: "\n")
            return
        }
        isConnecting = true
        authenticationGeneration &+= 1
        let generation = authenticationGeneration
        defer { if authenticationGeneration == generation { isConnecting = false } }
        do {
            let url = try await authentication.beginAuthorization()
            try Task.checkCancellation()
            guard authenticationGeneration == generation else { return }
            let callback = try await browser.authenticate(url: url, callbackScheme: configuration.callbackScheme)
            try Task.checkCancellation()
            guard authenticationGeneration == generation else { return }
            try await authentication.completeAuthorization(callbackURL: callback)
            guard authenticationGeneration == generation else { return }
            await updateAuthenticationState()
            guard authenticationGeneration == generation else { return }
            if isConnected {
                invalidatePlaybackContext()
                isDemo = false
                track = nil
                engine.reset(); updateFrame()
                status = .loading
                setForeground(foreground)
                record("Spotify authorization succeeded.")
            }
        } catch {
            guard authenticationGeneration == generation else { return }
            await authentication.cancelAuthorization()
            guard authenticationGeneration == generation else { return }
            if error is CancellationError || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                record("Authorization canceled.")
            } else { message = "Spotify authorization failed. Verify local configuration and try again." }
            await updateAuthenticationState()
        }
    }

    func disconnect() async {
        authenticationGeneration &+= 1
        isConnecting = false
        invalidatePlaybackContext()
        let generation = trackGeneration
        browser.cancel()
        do { try await authentication?.disconnect() }
        catch {
            guard trackGeneration == generation else { return }
            message = "Secure credentials could not be removed. Unlock the phone and retry disconnecting."
            await updateAuthenticationState()
            setForeground(foreground)
            return
        }
        guard trackGeneration == generation else { return }
        isConnected = false; isDemo = false
        track = nil; engine.reset(); updateFrame()
        status = .unauthorized
        setForeground(foreground)
        await activity.stop()
        record("Disconnected. To revoke app access, use Spotify account settings.")
    }

    func useDemo() async {
        invalidatePlaybackContext()
        let generation = trackGeneration
        await activity.stop()
        guard trackGeneration == generation else { return }
        isDemo = true
        track = SyntheticLyrics.demoTrack
        engine.reset()
        engine.update(snapshot: PlaybackSnapshot(track: track, position: 0, isPlaying: true), lyrics: SyntheticLyrics.demoDocument)
        engine.userTimingOffset = timingOffset
        parseWarnings = 0; status = .demo
        updateFrame(); setForeground(foreground)
        record("Started original synthetic lyric rehearsal.")
    }

    func resumeSpotify() async {
        invalidatePlaybackContext()
        let generation = trackGeneration
        await activity.stop()
        guard trackGeneration == generation else { return }
        isDemo = false
        engine.reset(); track = nil; updateFrame()
        status = isConnected ? .loading : .unauthorized
        setForeground(foreground)
    }

    func toggleDemoPlayback() {
        guard isDemo else { return }
        if frame.isPlaying { engine.pause() }
        else {
            if frame.position >= (track?.duration ?? 0) { engine.seek(to: 0) }
            engine.resume()
        }
        updateFrame()
    }

    func seekDemo(to position: Double) {
        guard isDemo else { return }
        engine.seek(to: position); updateFrame()
    }

    func refreshPlayback() async {
        guard foreground, !isDemo, isConnected, let client else { return }
        let generation = playbackGeneration
        playbackRequestGeneration &+= 1
        let requestGeneration = playbackRequestGeneration
        do {
            let snapshot = try await client.playbackState()
            guard acceptsPlayback(generation: generation, request: requestGeneration) else { return }
            let changed = track?.id != snapshot.track?.id
            if changed { trackGeneration &+= 1 }
            track = snapshot.track
            engine.apply(snapshot: snapshot)
            lastPlaybackAt = Date()
            hasFreshPlayback = snapshot.availability != .offline
            if changed {
                let lyricGeneration = lyricRequestGeneration
                let expectedTrack = trackGeneration
                let document = lyricsAllowed ? try await library.provider.lyrics(for: snapshot.track ?? emptyTrack) : nil
                guard acceptsPlayback(generation: generation, request: requestGeneration),
                      trackGeneration == expectedTrack, lyricRequestGeneration == lyricGeneration else { return }
                engine.setLyrics(document)
                parseWarnings = document?.warnings.count ?? 0
                record("Playback track changed.")
            }
            switch snapshot.availability {
            case .available: status = .ready
            case .noActiveDevice, .noContent: status = .noPlayback
            case .offline: status = .offline
            case .advertisement, .episode, .unsupported: status = .unsupported
            }
            updateFrame()
        } catch {
            guard acceptsPlayback(generation: generation, request: requestGeneration) else { return }
            await updateAuthenticationState()
            guard acceptsPlayback(generation: generation, request: requestGeneration) else { return }
            hasFreshPlayback = false
            lastPlaybackAt = nil
            if let failure = error as? SpotifyFailure {
                switch failure {
                case .rateLimited, .backingOff: status = .rateLimited
                case .authorizationDenied, .invalidResponse, .invalidConfiguration, .storageUnavailable: status = .error
                case .requiresAuthorization, .credentialsRevoked: status = .unauthorized
                default: status = isConnected ? .offline : .unauthorized
                }
            } else { status = isConnected ? .offline : .unauthorized }
            engine.pause(); updateFrame()
            await publishActivity(force: true)
            record(status == .rateLimited ? "Playback requests are waiting for the rate limit." : "Fresh playback is unavailable; the estimate is paused.")
        }
    }

    func importLyrics(from url: URL) async {
        let expectedTrack = trackGeneration
        let trackID = track?.id
        lyricRequestGeneration &+= 1
        let request = lyricRequestGeneration
        do {
            let document = try await library.importDocument(at: url, trackID: trackID)
            documents = library.entries
            if trackID != nil, trackGeneration == expectedTrack, lyricRequestGeneration == request,
               track?.id == trackID, lyricsAllowed {
                parseWarnings = document.warnings.count
                engine.setLyrics(document); updateFrame()
            }
            message = "Imported \(document.lines.count) timed lines. \(document.warnings.count) parsing warnings."
        } catch { message = error.localizedDescription }
    }

    func match(_ entryID: UUID) async {
        guard let track else { message = "Play a track or start rehearsal before matching a file."; return }
        let expectedTrack = trackGeneration
        lyricRequestGeneration &+= 1
        let request = lyricRequestGeneration
        do {
            let document = try await library.bind(entryID, to: track.id)
            documents = library.entries
            if trackGeneration == expectedTrack, lyricRequestGeneration == request,
               self.track?.id == track.id, lyricsAllowed {
                parseWarnings = document?.warnings.count ?? 0
                engine.setLyrics(document); updateFrame()
            }
        } catch { message = "The lyric match could not be saved." }
    }

    func remove(_ entryID: UUID) async {
        let expectedTrack = trackGeneration
        let selectedTrack = track
        lyricRequestGeneration &+= 1
        let request = lyricRequestGeneration
        do {
            try await library.remove(entryID)
            documents = library.entries
            if let selectedTrack, lyricsAllowed {
                let document = try await library.provider.lyrics(for: selectedTrack)
                guard trackGeneration == expectedTrack, lyricRequestGeneration == request,
                      track?.id == selectedTrack.id, lyricsAllowed else { return }
                engine.setLyrics(document)
                parseWarnings = document?.warnings.count ?? 0
                updateFrame()
            }
        } catch { message = "The lyric file could not be removed." }
    }

    func startActivity() async {
        guard track != nil else { message = "Start playback or rehearsal first."; return }
        let state = activityState
        lastActivityState = state
        lastActivityPublishedAt = Date()
        await activity.start(state: state)
        if let error = activity.lastError { message = error }
    }

    func stopActivity() async {
        lastActivityState = nil
        lastActivityPublishedAt = nil
        await activity.stop()
    }

    private func updateAuthenticationState() async {
        guard let authentication else { isConnected = false; return }
        let generation = authenticationGeneration
        let connected = await authentication.hasCredentials
        guard authenticationGeneration == generation else { return }
        isConnected = connected
    }

    private var emptyTrack: TrackMetadata { TrackMetadata(id: "", title: "", artist: "", duration: 0) }

    private func invalidatePlaybackContext() {
        playbackGeneration &+= 1
        trackGeneration &+= 1
        lyricRequestGeneration &+= 1
        pollTask?.cancel(); pollTask = nil
        clockTask?.cancel(); clockTask = nil
        hasFreshPlayback = false
        lastPlaybackAt = nil
        lastActivityState = nil
        lastActivityPublishedAt = nil
    }

    private func acceptsPlayback(generation: UInt64, request: UInt64) -> Bool {
        !Task.isCancelled && foreground && !isDemo && playbackGeneration == generation
            && playbackRequestGeneration == request
    }

    private func updateFrame() {
        frame = engine.frame()
        if !isDemo, activityIsStale, frame.isPlaying { engine.pause(); frame = engine.frame() }
        if isDemo, frame.isPlaying, let track, frame.position >= track.duration {
            engine.pause(); frame = engine.frame()
        }
    }

    private var activityState: CarLyricsActivityAttributes.ContentState {
        let bounded = LiveActivityViewState(track: track, frame: frame,
                                           privacy: privacyMode ? .hideLyrics : .showLyrics)
        let visible = lyricsAllowed && !privacyMode
        let playbackStatus: CarLyricsActivityAttributes.PlaybackStatus
        if activityIsStale { playbackStatus = .stale }
        else if track == nil || status == .noPlayback || status == .unsupported { playbackStatus = .unavailable }
        else { playbackStatus = frame.isPlaying ? .playing : .paused }
        return .init(title: privacyMode ? "" : bounded.trackTitle, artist: privacyMode ? "" : bounded.artist,
                     currentLine: visible && frame.current != nil ? bounded.currentLine : nil,
                     previousLine: visible && frame.previous != nil ? bounded.previousLine : nil,
                     nextLine: visible && frame.next != nil ? bounded.nextLine : nil,
                     playbackStatus: playbackStatus, privacyMode: privacyMode, isDemo: isDemo)
    }

    private func publishActivity(force: Bool = false) async {
        guard activity.isActive else { return }
        let state = activityState
        let now = Date()
        let heartbeat = foreground && !activityIsStale && now.timeIntervalSince(lastActivityPublishedAt ?? .distantPast) >= 10
        guard force || state != lastActivityState || heartbeat else { return }
        // Cache before awaiting so an older completion cannot undo a newer state.
        lastActivityState = state
        lastActivityPublishedAt = now
        await activity.update(state: state)
    }

    private func record(_ text: String) {
        diagnostics.insert("\(Date().formatted(date: .omitted, time: .standard)) · \(text)", at: 0)
        if diagnostics.count > 20 { diagnostics.removeLast(diagnostics.count - 20) }
    }
}
