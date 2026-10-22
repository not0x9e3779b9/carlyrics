import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section("Spotify") { ConnectionView(model: model) }
            Section("Live Activity privacy") {
                Toggle("Hide track and lyric details", isOn: $model.privacyMode)
                Text("Privacy mode sends only a generic session status. With details enabled, the system may show track and lyric content on the Lock Screen and paired displays.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Playback mode") {
                Button("Start synthetic rehearsal") { Task { await model.useDemo() } }
                if model.isDemo { Button("Return to Spotify metadata") { Task { await model.resumeSpotify() } } }
                Text("Spotify lyric synchronization is \(model.configuration.allowsSpotifyLyrics ? "enabled by local configuration" : "disabled pending permission"). Rehearsal uses original sample words and an independent clock.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Platform behavior") {
                Label("iOS 26 or later", systemImage: "iphone")
                Text("CarPlay uses a system-selected, non-interactive Live Activity layout. A wireless adapter only transports the connection.")
                Text("Leaving the foreground marks updates stale. There is no background polling service or server in this build.")
                Link("Spotify account access settings", destination: URL(string: "https://www.spotify.com/account/apps/")!)
                Link("Spotify synchronization policy", destination: URL(string: "https://developer.spotify.com/compliance-tips")!)
            }
            Section {
                NavigationLink("Diagnostics") { DiagnosticsView(model: model) }
                Text("CarLyrics 0.1 · License selection pending").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }
}

struct ConnectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.isConnected ? "Spotify connected" : "Connect Spotify", systemImage: model.isConnected ? "checkmark.shield" : "person.crop.circle")
                .font(.headline)
            Text("Read-only access to current playback and device availability. CarLyrics does not play audio or control Spotify.")
                .font(.callout).foregroundStyle(.secondary)
            if model.isConnected {
                Button("Disconnect Spotify", role: .destructive) { Task { await model.disconnect() } }
            } else {
                Button { Task { await model.connect() } } label: {
                    HStack { if model.isConnecting { ProgressView() }; Text(model.isConnecting ? "Connecting…" : "Connect Spotify") }
                }.buttonStyle(.borderedProminent).disabled(model.isConnecting)
            }
            ForEach(model.configuration.issues, id: \.self) { issue in
                Text(issue).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section("Current state") {
                LabeledContent("Playback", value: model.status.title)
                LabeledContent("Authentication", value: model.isConnected ? "Connected" : "Disconnected")
                LabeledContent("Lyrics source", value: model.isDemo ? "Original sample" : "Local import")
                LabeledContent("Parse warnings", value: "\(model.parseWarnings)")
                LabeledContent("Library documents", value: "\(model.documents.count)")
                LabeledContent("Clock", value: model.activityIsStale ? "Stale or inactive" : "Foreground estimate")
            }
            Section("Configuration") {
                if model.configuration.issues.isEmpty { Text("Public app configuration is complete.") }
                ForEach(model.configuration.issues, id: \.self) { Text($0) }
                Text("Credentials are held in Keychain. Diagnostic entries never include tokens or authorization callbacks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recent events") { ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()) } }
            Section("Unverified here") { Text("Native build, previews, physical authentication, background behavior, Lock Screen privacy, and wired/wireless CarPlay require Mac and device testing.") }
        }.navigationTitle("Diagnostics")
    }
}
