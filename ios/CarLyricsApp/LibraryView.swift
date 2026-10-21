import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var importing = false
    private var lrcType: UTType { UTType(filenameExtension: "lrc") ?? .plainText }

    var body: some View {
        List {
            Section {
                Text("Import lyrics you own or have permission to use. Files stay on this iPhone. Set up and match files while parked.")
                    .foregroundStyle(.secondary)
                Button { importing = true } label: { Label("Import .lrc file", systemImage: "square.and.arrow.down") }
            }
            Section("Your timed lyrics") {
                if model.documents.isEmpty {
                    ContentUnavailableView("Your words, your library", systemImage: "doc.text", description: Text("Import an LRC file with timestamps such as [00:05.00]."))
                }
                ForEach(model.documents) { document in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.filename).font(.headline)
                        Text(document.trackID == nil ? "Not matched to a track" : "Matched to a track")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Match to current track") { Task { await model.match(document.id) } }
                            .disabled(model.track == nil)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await model.remove(document.id) } } }
                }
            }
            if model.parseWarnings > 0 {
                Section("Import diagnostics") {
                    Text("\(model.parseWarnings) malformed entries were recovered or skipped. Check the original file if the timing looks wrong.")
                }
            }
            Section {
                Button("Try original sample lyrics") { Task { await model.useDemo() } }
                Text("No commercial lyrics or lyric-service access is included.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Lyrics library")
        .fileImporter(isPresented: $importing, allowedContentTypes: [lrcType, .plainText, .text], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await model.importLyrics(from: url) } }
            case .failure: model.message = "The document picker could not open this file."
            }
        }
    }
}
