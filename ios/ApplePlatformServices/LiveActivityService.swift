import ActivityKit
import Combine
import Foundation

/// Future APNs integration point. The default app supplies no sink and requests
/// no push token. Implementations must manage consent, authentication, and token
/// invalidation; these callbacks do not provide background execution time.
@MainActor
public protocol LiveActivityServerUpdateSink: AnyObject {
    func activityDidStart(id: String) async
    func activityDidReceivePushToken(id: String, token: Data) async
    func activityDidStop(id: String) async
}

public extension LiveActivityServerUpdateSink {
    func activityDidStart(id: String) async {}
    func activityDidReceivePushToken(id: String, token: Data) async {}
    func activityDidStop(id: String) async {}
}

@MainActor
public final class LiveActivityService: ObservableObject {
    public typealias State = CarLyricsActivityAttributes.ContentState

    @Published public private(set) var isActive = false
    @Published public private(set) var lastError: String?

    private var activity: Activity<CarLyricsActivityAttributes>?
    private var lastState: State?
    private var stateObservation: Task<Void, Never>?
    private var tokenObservation: Task<Void, Never>?
    private var contentRevision: UInt64 = 0
    private let serverUpdateSink: (any LiveActivityServerUpdateSink)?
    private let freshnessInterval: TimeInterval
    private let now: () -> Date

    // Leave room for ActivityKit's encoding overhead under the combined 4 KB cap.
    private static let payloadBudget = 3_800
    private static let maximumLifetime: TimeInterval = 8 * 60 * 60

    public init(
        serverUpdateSink: (any LiveActivityServerUpdateSink)? = nil,
        freshnessInterval: TimeInterval = 15,
        now: @escaping () -> Date = Date.init
    ) {
        self.serverUpdateSink = serverUpdateSink
        self.freshnessInterval = min(max(freshnessInterval, 1), 60)
        self.now = now
    }

    /// Attach to the newest active session after relaunch. End duplicate orphan
    /// sessions instead of leaving several CarLyrics surfaces behind.
    public func restore() {
        let candidates = Activity<CarLyricsActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .sorted { $0.attributes.startedAt > $1.attributes.startedAt }

        guard let newest = candidates.first else {
            detach()
            return
        }

        attach(newest)
        let restorationRevision = contentRevision
        let duplicates = Array(candidates.dropFirst())
        Task { [weak self] in
            for duplicate in duplicates {
                await duplicate.end(
                    ActivityContent(state: duplicate.content.state.privacyFiltered, staleDate: self?.now()),
                    dismissalPolicy: .immediate
                )
                await self?.serverUpdateSink?.activityDidStop(id: duplicate.id)
            }
            // A restored local snapshot is not evidence of fresh playback.
            if self?.activity?.id == newest.id, self?.contentRevision == restorationRevision {
                await self?.markStale()
            }
        }
    }

    public func start(state: State) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities are disabled in Settings."
            return
        }

        if activity == nil {
            restore()
        }
        if activity != nil {
            await update(state: state)
            return
        }

        let attributes = CarLyricsActivityAttributes(startedAt: now())
        let filteredState = state.privacyFiltered
        guard validate(attributes: attributes, state: filteredState) else { return }

        do {
            let requested = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: filteredState,
                    staleDate: staleDate(for: attributes, state: filteredState)
                ),
                pushType: serverUpdateSink == nil ? nil : .token
            )
            attach(requested)
            lastError = nil
            await serverUpdateSink?.activityDidStart(id: requested.id)
        } catch {
            lastError = "The system could not start the Live Activity. Try again after ending other activities."
        }
    }

    /// Updates are local and only run while iOS permits app execution. The stale
    /// deadline lets the widget communicate when foreground polling has stopped.
    public func update(state: State) async {
        guard let activity else { return }
        guard now() < activity.attributes.startedAt.addingTimeInterval(Self.maximumLifetime) else {
            await stop()
            lastError = "This Live Activity reached its eight-hour limit. Start a new session."
            return
        }

        let filteredState = state.privacyFiltered
        guard validate(attributes: activity.attributes, state: filteredState) else { return }
        contentRevision &+= 1
        let revision = contentRevision
        // A scene transition may interleave while ActivityKit is awaiting. Keep
        // the latest privacy choice available to that final stale update.
        lastState = filteredState
        await activity.update(ActivityContent(
            state: filteredState,
            staleDate: staleDate(for: activity.attributes, state: filteredState)
        ))
        guard self.activity?.id == activity.id, contentRevision == revision else { return }
        lastError = nil
    }

    /// Call when entering the background or losing fresh playback information.
    /// This is one final local update, not a request for continuous execution.
    public func markStale() async {
        guard let activity else { return }
        var state = (lastState ?? activity.content.state).privacyFiltered
        state.playbackStatus = .stale
        contentRevision &+= 1
        let revision = contentRevision
        lastState = state
        await activity.update(ActivityContent(state: state, staleDate: now()))
        guard self.activity?.id == activity.id, contentRevision == revision else { return }
    }

    /// Stop all sessions with these attributes, including an unobserved session
    /// left by a previous process. Immediate dismissal avoids lingering lyrics.
    public func stop() async {
        let sessions = Activity<CarLyricsActivityAttributes>.activities
        detach()
        for session in sessions {
            var finalState = session.content.state.privacyFiltered
            finalState.playbackStatus = .unavailable
            finalState.previousLine = nil
            finalState.currentLine = nil
            finalState.nextLine = nil
            await session.end(
                ActivityContent(state: finalState, staleDate: now()),
                dismissalPolicy: .immediate
            )
            await serverUpdateSink?.activityDidStop(id: session.id)
        }
        lastError = nil
    }

    private func staleDate(for attributes: CarLyricsActivityAttributes, state: State) -> Date {
        if state.playbackStatus == .stale {
            return now()
        }
        return min(
            now().addingTimeInterval(freshnessInterval),
            attributes.startedAt.addingTimeInterval(Self.maximumLifetime)
        )
    }

    private func validate(attributes: CarLyricsActivityAttributes, state: State) -> Bool {
        struct Payload: Encodable {
            let attributes: CarLyricsActivityAttributes
            let contentState: State
        }
        do {
            let bytes = try JSONEncoder().encode(Payload(attributes: attributes, contentState: state)).count
            guard bytes <= Self.payloadBudget else {
                lastError = "Live Activity content is too large. Use shorter lyric lines or metadata only."
                return false
            }
            return true
        } catch {
            lastError = "Live Activity content could not be encoded."
            return false
        }
    }

    private func attach(_ session: Activity<CarLyricsActivityAttributes>) {
        detach()
        activity = session
        lastState = session.content.state.privacyFiltered
        isActive = session.activityState == .active || session.activityState == .stale

        stateObservation = Task { [weak self] in
            for await state in session.activityStateUpdates {
                guard !Task.isCancelled, self?.activity?.id == session.id else { return }
                switch state {
                case .active, .stale:
                    self?.isActive = true
                case .pending:
                    // Scheduled activities remain observed until the system
                    // starts them; they have no active presentation yet.
                    self?.isActive = false
                case .ended, .dismissed:
                    self?.detach()
                    await self?.serverUpdateSink?.activityDidStop(id: session.id)
                    return
                @unknown default:
                    self?.detach()
                    return
                }
            }
        }

        if let serverUpdateSink {
            tokenObservation = Task { [weak self] in
                for await token in session.pushTokenUpdates {
                    guard !Task.isCancelled, self?.activity?.id == session.id else { return }
                    await serverUpdateSink.activityDidReceivePushToken(id: session.id, token: token)
                }
            }
        }
    }

    private func detach() {
        contentRevision &+= 1
        stateObservation?.cancel()
        tokenObservation?.cancel()
        stateObservation = nil
        tokenObservation = nil
        activity = nil
        lastState = nil
        isActive = false
    }

    deinit {
        stateObservation?.cancel()
        tokenObservation?.cancel()
    }
}
