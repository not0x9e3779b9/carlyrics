import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CarLyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarLyricsLiveActivity()
    }
}

struct CarLyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CarLyricsActivityAttributes.self) { context in
            SupplementalActivityView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.privacyMode ? "lock.fill" : "music.note")
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatusView(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MediumActivityView(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: context.state.privacyMode ? "lock.fill" : "music.note")
                    .accessibilityLabel(context.state.privacyMode ? "CarLyrics content hidden" : "CarLyrics")
            } compactTrailing: {
                CompactActivityView(state: context.state, isStale: context.isStale)
            } minimal: {
                Image(systemName: context.state.privacyMode ? "lock.fill" : statusSymbol(
                    state: context.state,
                    isStale: context.isStale
                ))
                .accessibilityLabel(statusDescription(state: context.state, isStale: context.isStale))
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct SupplementalActivityView: View {
    @Environment(\.activityFamily) private var activityFamily
    let state: CarLyricsActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            switch activityFamily {
            case .small:
                SmallActivityView(state: state, isStale: isStale)
            case .medium:
                MediumActivityView(state: state, isStale: isStale)
                    .padding()
            @unknown default:
                SmallActivityView(state: state, isStale: isStale)
            }
        }
        .privacySensitive()
    }
}

/// CarPlay and the watchOS Smart Stack share this non-scrolling small layout.
/// CarPlay disables interactive elements, so this view contains only content.
private struct SmallActivityView: View {
    let state: CarLyricsActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.privacyMode {
                Label("CarLyrics", systemImage: "lock.fill")
                    .font(.headline)
                Text("Content hidden")
                    .font(.subheadline)
                ActivityStatusView(state: state, isStale: isStale)
            } else {
                HStack(spacing: 6) {
                    Text(state.isDemo ? "CarLyrics demo" : "CarLyrics")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    CompactActivityView(state: state, isStale: isStale)
                }
                if isStale || state.playbackStatus == .stale {
                    Text("Waiting for fresh playback")
                        .font(.headline)
                        .lineLimit(2)
                } else {
                    Text(primaryLine(state: state))
                        .font(.headline)
                        .lineLimit(2)
                }
                Text(metadata(state: state))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
}

private struct MediumActivityView: View {
    let state: CarLyricsActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.privacyMode {
                Label("CarLyrics", systemImage: "lock.fill")
                    .font(.headline)
                Text("Playback details and lyrics are hidden")
                    .font(.subheadline)
                ActivityStatusView(state: state, isStale: isStale)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title.isEmpty ? "CarLyrics" : state.title)
                            .font(.headline)
                            .lineLimit(1)
                        if !state.artist.isEmpty {
                            Text(state.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    ActivityStatusView(state: state, isStale: isStale)
                }
                if isStale || state.playbackStatus == .stale {
                    Text("Waiting for fresh playback")
                        .font(.headline)
                    Text("Open CarLyrics when it is safe to refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if let previousLine = nonempty(state.previousLine) {
                        Text(previousLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityLabel("Previous line: \(previousLine)")
                    }
                    Text(primaryLine(state: state))
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityLabel("Current: \(primaryLine(state: state))")
                    if let nextLine = nonempty(state.nextLine) {
                        Text(nextLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityLabel("Next line: \(nextLine)")
                    }
                }
                if state.isDemo {
                    Text("Original demo lyrics")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }
}

private struct ActivityStatusView: View {
    let state: CarLyricsActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Label(
            statusDescription(state: state, isStale: isStale),
            systemImage: statusSymbol(state: state, isStale: isStale)
        )
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .privacySensitive()
    }
}

private struct CompactActivityView: View {
    let state: CarLyricsActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Image(systemName: state.privacyMode ? "lock.fill" : statusSymbol(state: state, isStale: isStale))
            .accessibilityLabel(state.privacyMode ? "Content hidden" : statusDescription(state: state, isStale: isStale))
            .privacySensitive()
    }
}

private func nonempty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return value
}

private func primaryLine(state: CarLyricsActivityAttributes.ContentState) -> String {
    if state.playbackStatus == .unavailable { return "No playback available" }
    if let line = state.currentLine {
        return nonempty(line) ?? "Instrumental"
    }
    if nonempty(state.nextLine) != nil { return "Waiting for the first line" }
    return "Playback metadata only"
}

private func metadata(state: CarLyricsActivityAttributes.ContentState) -> String {
    [state.title, state.artist].filter { !$0.isEmpty }.joined(separator: " · ")
}

private func statusDescription(state: CarLyricsActivityAttributes.ContentState, isStale: Bool) -> String {
    if isStale || state.playbackStatus == .stale { return "Out of date" }
    switch state.playbackStatus {
    case .playing: return "Playing"
    case .paused: return "Paused"
    case .stale: return "Out of date"
    case .unavailable: return "Unavailable"
    }
}

private func statusSymbol(state: CarLyricsActivityAttributes.ContentState, isStale: Bool) -> String {
    if isStale || state.playbackStatus == .stale { return "clock.badge.exclamationmark" }
    switch state.playbackStatus {
    case .playing: return "music.note"
    case .paused: return "pause.fill"
    case .stale: return "clock.badge.exclamationmark"
    case .unavailable: return "minus.circle"
    }
}

private extension CarLyricsActivityAttributes {
    static var preview: Self { Self() }
}

private extension CarLyricsActivityAttributes.ContentState {
    static var demoPreview: Self {
        Self(
            title: "Lantern Road",
            artist: "CarLyrics Demo",
            currentLine: "Every lantern lights the way",
            previousLine: "Soft horizons greet the day",
            nextLine: "We carry morning in our hands",
            isDemo: true
        )
    }

    static var pausedPreview: Self {
        var state = demoPreview
        state.playbackStatus = .paused
        return state
    }

    static var stalePreview: Self {
        var state = demoPreview
        state.playbackStatus = .stale
        return state
    }

    static var privatePreview: Self {
        var state = demoPreview
        state.privacyMode = true
        return state.privacyFiltered
    }
}

#Preview("Lock Screen", as: .content, using: CarLyricsActivityAttributes.preview) {
    CarLyricsLiveActivity()
} contentStates: {
    CarLyricsActivityAttributes.ContentState.demoPreview
    CarLyricsActivityAttributes.ContentState.pausedPreview
    CarLyricsActivityAttributes.ContentState.stalePreview
    CarLyricsActivityAttributes.ContentState.privatePreview
    CarLyricsActivityAttributes.ContentState(title: "Lantern Road", artist: "CarLyrics Demo")
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: CarLyricsActivityAttributes.preview) {
    CarLyricsLiveActivity()
} contentStates: {
    CarLyricsActivityAttributes.ContentState.demoPreview
    CarLyricsActivityAttributes.ContentState.privatePreview
}

#Preview("CarPlay small: synthetic demo") {
    SmallActivityView(state: .demoPreview, isStale: false)
        .padding(8)
        .frame(width: 240, height: 100)
}

#Preview("CarPlay small: stale") {
    SmallActivityView(state: .stalePreview, isStale: true)
        .padding(8)
        .frame(width: 170, height: 78)
}

#Preview("CarPlay small: private") {
    SmallActivityView(state: .privatePreview, isStale: false)
        .padding(8)
        .frame(width: 240, height: 78)
}
