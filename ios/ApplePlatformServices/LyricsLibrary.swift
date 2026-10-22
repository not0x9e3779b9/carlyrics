import Foundation
import LyricsCore

@MainActor
final class LyricsLibrary {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let filename: String
        let text: String
        var trackID: String?
    }

    private(set) var entries: [Entry] = []
    private let location: URL
    let provider = LocalLRCProvider()
    private var providerUpdate: Task<Void, Never>?
    private var registeredTrackIDs: Set<String> = []

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CarLyrics", isDirectory: true)
        location = directory.appendingPathComponent("lyrics-library.json")
    }

    func restore() async throws {
        guard FileManager.default.fileExists(atPath: location.path) else { return }
        entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: location))
        await synchronizeProvider()
    }

    func importDocument(at url: URL, trackID: String?) async throws -> LyricsDocument {
        guard url.pathExtension.lowercased() == "lrc" else { throw LibraryError.wrongType }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 2_000_000 else { throw LibraryError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 2_000_000 else { throw LibraryError.tooLarge }
        let text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let utf16 = String(data: data, encoding: .utf16) { text = utf16 }
        else if let utf8 = String(data: data, encoding: .utf8) { text = utf8 }
        else if let utf16 = String(data: data, encoding: .utf16) { text = utf16 }
        else { throw LibraryError.encoding }
        let document = LRCParser().parse(text)
        guard !document.lines.isEmpty else { throw LibraryError.noTimestamps }
        let entry = Entry(id: UUID(), filename: url.lastPathComponent, text: text, trackID: trackID)
        var updated = entries.map { entry -> Entry in
            var retained = entry
            if let trackID, retained.trackID == trackID { retained.trackID = nil }
            return retained
        }
        updated.append(entry)
        try persist(updated)
        entries = updated
        await synchronizeProvider()
        return document
    }

    func bind(_ entryID: UUID, to trackID: String) async throws -> LyricsDocument? {
        guard let selected = entries.first(where: { $0.id == entryID }) else { return nil }
        let updated = entries.map { entry -> Entry in
            var result = entry
            if result.trackID == trackID { result.trackID = nil }
            if result.id == entryID { result.trackID = trackID }
            return result
        }
        try persist(updated)
        entries = updated
        let document = LRCParser().parse(selected.text)
        await synchronizeProvider()
        return document
    }

    func remove(_ entryID: UUID) async throws {
        let updated = entries.filter { $0.id != entryID }
        try persist(updated)
        entries = updated
        await synchronizeProvider()
    }

    /// Commit the library before awaiting, then serialize provider snapshots in
    /// the same order. A suspended old unbind cannot delete a newer binding.
    private func synchronizeProvider() async {
        let snapshot = entries
        let previous = providerUpdate
        let oldTrackIDs = registeredTrackIDs
        let newTrackIDs = Set(snapshot.compactMap(\.trackID))
        registeredTrackIDs = newTrackIDs
        let provider = self.provider
        let operation = Task {
            if let previous { await previous.value }
            for trackID in oldTrackIDs.subtracting(newTrackIDs) {
                await provider.removeLyrics(for: trackID)
            }
            for entry in snapshot {
                if let trackID = entry.trackID {
                    _ = await provider.importLyrics(entry.text, for: trackID)
                }
            }
        }
        providerUpdate = operation
        await operation.value
    }

    private func persist(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: location, options: [.atomic, .completeFileProtection])
    }

    enum LibraryError: LocalizedError {
        case wrongType, tooLarge, encoding, noTimestamps
        var errorDescription: String? {
            switch self {
            case .wrongType: return "Choose an .lrc file."
            case .tooLarge: return "Choose a lyric file smaller than 2 MB."
            case .encoding: return "The file must contain UTF-8 or UTF-16 text."
            case .noTimestamps: return "No valid timed lines were found. Check timestamps such as [00:05.00]."
            }
        }
    }
}
