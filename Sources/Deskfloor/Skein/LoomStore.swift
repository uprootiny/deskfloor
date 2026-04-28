import Foundation

/// Loom state: visible warps, fired wefts, and the artifact shelf.
///
/// Persisted in `~/.deskfloor/loom.json` (single document, schema-versioned).
@Observable
final class LoomStore {
    var schemaVersion: Int = 1
    /// Ordered list of thread IDs visible as warps. Capped at 7 by design.
    private(set) var visibleWarps: [UUID] = []
    /// Fired wefts, oldest first. FIFO-evicted past `weftCap`.
    private(set) var wefts: [Weft] = []
    /// Excerpt IDs collected on the bottom shelf, oldest first.
    private(set) var shelfExcerptIDs: [UUID] = []
    /// True once seedOnce has populated visibleWarps from skein.
    /// Prevents a cleared warp set from being silently re-populated on next view appear.
    private(set) var hasSeeded: Bool = false

    /// Maximum retained wefts. Older are FIFO-evicted on append.
    /// At ~1 KB per weft this caps the store around 50 KB; revisit if responses grow.
    private let weftCap: Int = 50

    private let storeURL: URL

    /// Debounce window for save coalescing. Picker sessions and future
    /// streaming-response updates fire bursts of mutations; without coalescing
    /// each writes the whole snapshot to disk. With this, all mutations within
    /// 200 ms produce a single write.
    private let saveDebounce: TimeInterval = 0.2
    private var pendingSaveWorkItem: DispatchWorkItem?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".deskfloor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("loom.json")
        load()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var schemaVersion: Int
        var visibleWarps: [UUID]
        var wefts: [Weft]
        var shelfExcerptIDs: [UUID]
        var hasSeeded: Bool
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else { return }
        schemaVersion = snap.schemaVersion
        visibleWarps = snap.visibleWarps
        wefts = snap.wefts
        shelfExcerptIDs = snap.shelfExcerptIDs
        hasSeeded = snap.hasSeeded
    }

    /// Coalesce rapid mutations into a single write.
    func save() {
        pendingSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushSave()
        }
        pendingSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounce, execute: work)
    }

    /// Force an immediate flush. Useful before app termination or migration.
    func flushSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        let snap = Snapshot(
            schemaVersion: schemaVersion,
            visibleWarps: visibleWarps,
            wefts: wefts,
            shelfExcerptIDs: shelfExcerptIDs,
            hasSeeded: hasSeeded
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snap) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Warp mutations

    func setVisibleWarps(_ ids: [UUID]) {
        visibleWarps = Array(ids.prefix(7))
        save()
    }

    func addWarp(_ id: UUID) {
        guard !visibleWarps.contains(id), visibleWarps.count < 7 else { return }
        visibleWarps.append(id)
        save()
    }

    func removeWarp(_ id: UUID) {
        visibleWarps.removeAll { $0 == id }
        save()
    }

    /// Populate from the most-recently-updated threads exactly once.
    /// Safe to call on every view appear; subsequent calls are no-ops.
    func seedOnce(from skein: SkeinStore, count: Int = 3) {
        guard !hasSeeded, !skein.threads.isEmpty else { return }
        let recent = skein.recentThreads.prefix(count).map(\.id)
        visibleWarps = Array(recent)
        hasSeeded = true
        save()
    }

    // MARK: - Weft mutations

    /// Fire a weft across all currently-visible warps. Pre-seeds one
    /// pending Response per warp so the UI can render placeholder slots
    /// immediately. Real dispatch (or a debug-only DemoDispatcher) fills
    /// the responses asynchronously.
    @discardableResult
    func fireWeft(prompt: String, anchorTurn: Int) -> Weft {
        let pending = visibleWarps.map { Weft.Response(warpID: $0, status: .pending) }
        let weft = Weft(
            prompt: prompt,
            warpIDs: visibleWarps,
            anchorTurn: anchorTurn,
            responses: pending
        )
        wefts.append(weft)
        if wefts.count > weftCap {
            wefts.removeFirst(wefts.count - weftCap)
        }
        save()
        return weft
    }

    /// External completion hook — called by the dispatcher (real or demo)
    /// when a warp's response arrives. No-op if the weft or response was evicted.
    func completeResponse(weftID: UUID, responseID: UUID, content: String) {
        guard let wIdx = wefts.firstIndex(where: { $0.id == weftID }),
              let rIdx = wefts[wIdx].responses.firstIndex(where: { $0.id == responseID })
        else { return }
        wefts[wIdx].responses[rIdx].content = content
        wefts[wIdx].responses[rIdx].status = .complete
        wefts[wIdx].responses[rIdx].receivedAt = Date()
        save()
    }

    /// External streaming hook — incremental content append.
    func streamResponse(weftID: UUID, responseID: UUID, appendingContent: String) {
        guard let wIdx = wefts.firstIndex(where: { $0.id == weftID }),
              let rIdx = wefts[wIdx].responses.firstIndex(where: { $0.id == responseID })
        else { return }
        wefts[wIdx].responses[rIdx].content += appendingContent
        wefts[wIdx].responses[rIdx].status = .streaming
        save()
    }

    // MARK: - Shelf mutations

    func addToShelf(excerptID: UUID) {
        guard !shelfExcerptIDs.contains(excerptID) else { return }
        shelfExcerptIDs.append(excerptID)
        save()
    }

    func removeFromShelf(excerptID: UUID) {
        shelfExcerptIDs.removeAll { $0 == excerptID }
        save()
    }
}
