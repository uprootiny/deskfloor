import Foundation

/// Central store for all conversation threads, splices, excerpts, and compositions.
@Observable
final class SkeinStore {
    var threads: [Thread] = []
    var splices: [Splice] = []
    var excerpts: [Excerpt] = []
    var compositions: [Composition] = []

    private let baseDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        baseDir = home.appendingPathComponent(".deskfloor/skein", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    func load() {
        threads = loadJSON("threads.json") ?? []
        splices = loadJSON("splices.json") ?? []
        excerpts = loadJSON("excerpts.json") ?? []
        compositions = loadJSON("compositions.json") ?? []
    }

    func save() {
        saveJSON("threads.json", threads)
        saveJSON("splices.json", splices)
        saveJSON("excerpts.json", excerpts)
        saveJSON("compositions.json", compositions)
    }

    private func loadJSON<T: Decodable>(_ filename: String) -> T? {
        let url = baseDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ filename: String, _ value: T) {
        let url = baseDir.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Thread Operations

    func addThread(_ thread: Thread) {
        threads.append(thread)
        save()
    }

    func updateThread(_ thread: Thread) {
        if let idx = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[idx] = thread
            save()
        }
    }

    func setThreadStatus(_ threadID: UUID, _ status: SessionStatus) {
        if let idx = threads.firstIndex(where: { $0.id == threadID }) {
            threads[idx].status = status
            save()
        }
    }

    func tagThread(_ threadID: UUID, tag: String) {
        if let idx = threads.firstIndex(where: { $0.id == threadID }) {
            if !threads[idx].tags.contains(tag) {
                threads[idx].tags.append(tag)
                save()
            }
        }
    }

    func linkThreadToProject(_ threadID: UUID, projectID: UUID) {
        if let idx = threads.firstIndex(where: { $0.id == threadID }) {
            if !threads[idx].projectLinks.contains(projectID) {
                threads[idx].projectLinks.append(projectID)
                save()
            }
        }
    }

    // MARK: - Turn Annotations

    func bookmarkTurn(threadID: UUID, turnID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }),
              let uIdx = threads[tIdx].turns.firstIndex(where: { $0.id == turnID }) else { return }
        threads[tIdx].turns[uIdx].isBookmarked.toggle()
        save()
    }

    func markDeadEnd(threadID: UUID, turnID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }),
              let uIdx = threads[tIdx].turns.firstIndex(where: { $0.id == turnID }) else { return }
        threads[tIdx].turns[uIdx].isDeadEnd.toggle()
        save()
    }

    func markBreakthrough(threadID: UUID, turnID: UUID) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }),
              let uIdx = threads[tIdx].turns.firstIndex(where: { $0.id == turnID }) else { return }
        threads[tIdx].turns[uIdx].isBreakthrough.toggle()
        save()
    }

    func annotateTurn(threadID: UUID, turnID: UUID, text: String) {
        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }),
              let uIdx = threads[tIdx].turns.firstIndex(where: { $0.id == turnID }) else { return }
        threads[tIdx].turns[uIdx].annotations.append(Annotation(text: text))
        save()
    }

    // MARK: - Splices

    func splice(from: (thread: UUID, turn: UUID), to: (thread: UUID, turn: UUID), label: String) {
        let s = Splice(fromThread: from.thread, fromTurn: from.turn,
                        toThread: to.thread, toTurn: to.turn, label: label)
        splices.append(s)
        save()
    }

    // MARK: - Excerpts

    func extractExcerpt(threadID: UUID, turnID: UUID, content: String,
                         kind: Artifact.Kind, column: Excerpt.Column) {
        let excerpt = Excerpt(sourceThread: threadID, sourceTurn: turnID,
                               content: content, kind: kind, column: column)
        excerpts.append(excerpt)
        save()
    }

    func moveExcerpt(_ excerptID: UUID, to column: Excerpt.Column) {
        if let idx = excerpts.firstIndex(where: { $0.id == excerptID }) {
            excerpts[idx].column = column
            save()
        }
    }

    func deleteExcerpt(_ excerptID: UUID) {
        excerpts.removeAll { $0.id == excerptID }
        save()
    }

    // MARK: - Compositions

    func createComposition(title: String) -> Composition {
        let comp = Composition(title: title)
        compositions.append(comp)
        save()
        return comp
    }

    func addToComposition(_ compositionID: UUID, excerpt: Excerpt) {
        guard let idx = compositions.firstIndex(where: { $0.id == compositionID }) else { return }
        let piece = Composition.Piece(excerptID: excerpt.id, content: excerpt.content,
                                       label: "From thread")
        compositions[idx].pieces.append(piece)
        save()
    }

    func updateComposition(_ composition: Composition) {
        if let idx = compositions.firstIndex(where: { $0.id == composition.id }) {
            compositions[idx] = composition
            save()
        }
    }

    // MARK: - Queries

    func threadsForProject(_ projectID: UUID) -> [Thread] {
        threads.filter { $0.projectLinks.contains(projectID) }
    }

    func threadsBySource(_ source: Thread.Source) -> [Thread] {
        threads.filter { $0.source == source }
    }

    func excerptsByColumn(_ column: Excerpt.Column) -> [Excerpt] {
        excerpts.filter { $0.column == column }
    }

    func splicesForThread(_ threadID: UUID) -> [Splice] {
        splices.filter { $0.fromThread == threadID || $0.toThread == threadID }
    }

    /// All threads sorted by most recently updated.
    var recentThreads: [Thread] {
        threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Summary stats.
    var stats: (threads: Int, turns: Int, artifacts: Int, excerpts: Int) {
        let turnCount = threads.reduce(0) { $0 + $1.turns.count }
        let artifactCount = threads.reduce(0) { $0 + $1.artifactCount }
        return (threads.count, turnCount, artifactCount, excerpts.count)
    }
}
