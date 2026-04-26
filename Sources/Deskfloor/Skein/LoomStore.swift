import Foundation

/// Loom state: visible warps, fired wefts, and the artifact shelf.
///
/// Persisted in `~/.deskfloor/loom.json` (single document, schema-versioned).
@Observable
final class LoomStore {
    var schemaVersion: Int = 1
    /// Ordered list of thread IDs visible as warps. Capped at 7 by design.
    var visibleWarps: [UUID] = []
    /// Fired wefts, oldest first.
    var wefts: [Weft] = []
    /// Excerpt IDs collected on the bottom shelf, oldest first.
    var shelfExcerptIDs: [UUID] = []
    /// True once seedOnce has populated visibleWarps from skein.
    /// Prevents a cleared warp set from being silently re-populated on next view appear.
    var hasSeeded: Bool = false

    private let storeURL: URL

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

    func save() {
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
    /// immediately. Mock responses populate via staggered timer.
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
        save()
        scheduleMockResponses(for: weft.id)
        return weft
    }

    /// Stub: fill each pending response with a placeholder string after a
    /// per-warp delay. Real LLM dispatch slots in here later.
    private func scheduleMockResponses(for weftID: UUID) {
        guard let weft = wefts.first(where: { $0.id == weftID }) else { return }
        for (idx, response) in weft.responses.enumerated() {
            let delay = 0.22 + Double(idx) * 0.14
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.completeMockResponse(
                    weftID: weftID,
                    responseID: response.id,
                    content: "[mock] response from warp \(idx + 1)"
                )
            }
        }
    }

    private func completeMockResponse(weftID: UUID, responseID: UUID, content: String) {
        guard let wIdx = wefts.firstIndex(where: { $0.id == weftID }),
              let rIdx = wefts[wIdx].responses.firstIndex(where: { $0.id == responseID })
        else { return }
        wefts[wIdx].responses[rIdx].content = content
        wefts[wIdx].responses[rIdx].status = .complete
        wefts[wIdx].responses[rIdx].receivedAt = Date()
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
