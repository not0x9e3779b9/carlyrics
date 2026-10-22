import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("completedOnboarding") private var completedOnboarding = false

    var body: some View {
        TabView {
            NavigationStack { NowPlayingView(model: model) }
                .tabItem { Label("Now Playing", systemImage: "waveform") }
            NavigationStack { LibraryView(model: model) }
                .tabItem { Label("Lyrics", systemImage: "text.alignleft") }
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: Binding(get: { !completedOnboarding }, set: { completedOnboarding = !$0 })) {
            OnboardingView { completedOnboarding = true }
                .interactiveDismissDisabled()
        }
        .alert("CarLyrics", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

struct OnboardingView: View {
    let finish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 56)).foregroundStyle(.indigo).accessibilityHidden(true)
                Text("A little closer\nto every line.").font(.largeTitle.bold())
                Text("Bring your own timed lyrics. Rehearse with original sample lines, or connect Spotify for read-only playback information.")
                    .font(.title3).foregroundStyle(.secondary)
                Label("Prepare and import files while parked.", systemImage: "car.side.lock.fill")
                Label("Live Activities may appear in supported CarPlay surfaces on iOS 26. The system controls their placement.", systemImage: "rectangle.inset.filled")
                Label("When the app is suspended, lyric updates can become stale. Continuous background synchronization is not available.", systemImage: "clock.badge.exclamationmark")
                Text("Spotify synchronization requires permission under Spotify’s policies. This build keeps live Spotify metadata separate from the synthetic lyric rehearsal.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Get started", action: finish).buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity)
            }.padding(28)
        }.background(Color(.systemGroupedBackground))
    }
}
