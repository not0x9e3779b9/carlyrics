import SwiftUI
import LyricsCore

struct NowPlayingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label(model.isDemo ? "REHEARSAL" : "CARLYRICS", systemImage: model.isDemo ? "sparkle" : "waveform")
                        .font(.caption.weight(.bold)).tracking(2)
                    Spacer()
                    if model.status == .loading { ProgressView().accessibilityLabel("Loading playback") }
                    else { Image(systemName: model.frame.isPlaying ? "waveform.circle.fill" : "pause.circle").accessibilityHidden(true) }
                }.foregroundStyle(.secondary)

                if let track = model.track {
                    trackHeader(track)
                    lyricCard
                    VStack(spacing: 6) {
                        ProgressView(value: min(max(model.frame.position, 0), max(track.duration, 1)), total: max(track.duration, 1))
                            .accessibilityLabel("Playback progress")
                            .accessibilityValue("\(time(model.frame.position)) of \(time(track.duration))")
                        HStack {
                            Text(time(model.frame.position))
                            Spacer()
                            Text(time(track.duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if model.isDemo { rehearsalControls(duration: track.duration) }
                    ActivityControls(model: model, service: model.activity)
                } else {
                    ContentUnavailableView(model.status.title, systemImage: "quote.bubble", description: Text("Play a song in Spotify, or explore the original sample lyric rehearsal."))
                    Button("Try lyric rehearsal") { Task { await model.useDemo() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    ConnectionView(model: model)
                }

                if model.status != .ready && model.status != .demo && model.status != .empty {
                    Label(model.status.title, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                if model.track != nil {
                    offsetControls
                    Text("Prepare while parked. CarPlay presentation and refresh timing are controlled by iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshPlayback() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: model.status)
    }

    private func trackHeader(_ track: TrackMetadata) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if let artwork = track.artworkURL, !model.isDemo {
                AsyncImage(url: artwork) { image in image.resizable().scaledToFit() }
                placeholder: { Image(systemName: "music.note").font(.title) }
                    .frame(width: 80, height: 80).accessibilityLabel("Album artwork")
            } else {
                Image(systemName: "music.note.list")
                    .font(.largeTitle).foregroundStyle(.indigo)
                    .frame(width: 72, height: 72).background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(track.artist).font(.body).foregroundStyle(.secondary)
                if !track.album.isEmpty { Text(track.album).font(.caption).foregroundStyle(.secondary) }
                if let url = track.spotifyURL, !model.isDemo {
                    Link("Listen on Spotify", destination: url).font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var lyricCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(model.lyricsAllowed ? "IN THE MOMENT" : "PLAYBACK INFORMATION", systemImage: "quote.opening")
                .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            if !model.lyricsAllowed {
                Text("Connected. Lyrics stay in rehearsal.").font(.title2.bold())
                Text("Spotify’s policies restrict lyric synchronization. Your imported library stays local and available for independent rehearsal.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !model.hasLyrics {
                Text("A space for your words.").font(.title2.bold())
                Text("Import a timed .lrc file in Lyrics and match it to this track.").foregroundStyle(.secondary)
            } else {
                Text(model.frame.previous?.text ?? " ").font(.body).foregroundStyle(.secondary).lineLimit(2)
                Text(model.frame.current.map { $0.text.isEmpty ? "Instrumental" : $0.text } ?? "Waiting for the first line…")
                    .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Current lyric")
                Text(model.frame.next?.text ?? " ").font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
    }

    private var offsetControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lyric timing").font(.headline)
                Spacer()
                Text(String(format: "%+.1f s", model.timingOffset)).monospacedDigit()
            }
            Stepper("Adjust by 0.1 seconds", value: $model.timingOffset, in: -10...10, step: 0.1)
                .accessibilityValue(String(format: "%+.1f seconds", model.timingOffset))
            Text("Positive values show lines earlier.").font(.footnote).foregroundStyle(.secondary)
            if model.timingOffset != 0 { Button("Reset timing") { model.timingOffset = 0 } }
        }
    }

    private func rehearsalControls(duration: Double) -> some View {
        VStack {
            HStack(spacing: 32) {
                Button { model.seekDemo(to: max(0, model.frame.position - 5)) } label: { Image(systemName: "gobackward.5") }
                    .accessibilityLabel("Rewind rehearsal five seconds")
                Button { model.toggleDemoPlayback() } label: { Image(systemName: model.frame.isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(model.frame.isPlaying ? "Pause rehearsal" : "Resume rehearsal")
                Button { model.seekDemo(to: min(duration, model.frame.position + 5)) } label: { Image(systemName: "goforward.5") }
                    .accessibilityLabel("Advance rehearsal five seconds")
            }.font(.title2).buttonStyle(.bordered).controlSize(.large)
            Text("Original sample · no audio is played").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct ActivityControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var service: LiveActivityService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.isActive {
                Button { Task { await model.stopActivity() } } label: { Label("Stop Live Activity", systemImage: "stop.circle") }
                    .buttonStyle(.bordered)
            } else {
                Button { Task { await model.startActivity() } } label: { Label("Start Live Activity", systemImage: "rectangle.inset.filled") }
                    .buttonStyle(.borderedProminent)
            }
            Text("An optional glanceable view for your Lock Screen and supported CarPlay displays. Background updates can stop.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
