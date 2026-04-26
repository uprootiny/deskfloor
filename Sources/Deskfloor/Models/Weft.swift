import Foundation

/// One prompt fanned across multiple warps at a single anchor row.
/// The Loom analogue of a weft thread crossing the warp.
///
/// Persisted in `~/.deskfloor/loom.json` via `LoomStore`.
struct Weft: Identifiable, Codable, Hashable {
    let id: UUID
    var prompt: String
    var warpIDs: [UUID]
    var anchorTurn: Int
    var responses: [Response]
    var firedAt: Date

    init(id: UUID = UUID(),
         prompt: String,
         warpIDs: [UUID],
         anchorTurn: Int,
         responses: [Response] = [],
         firedAt: Date = Date()) {
        self.id = id
        self.prompt = prompt
        self.warpIDs = warpIDs
        self.anchorTurn = anchorTurn
        self.responses = responses
        self.firedAt = firedAt
    }

    func response(for warpID: UUID) -> Response? {
        responses.first(where: { $0.warpID == warpID })
    }

    /// One response from one warp. Status carries the lifecycle so the UI
    /// can render pending/streaming/error states distinctly.
    struct Response: Identifiable, Codable, Hashable {
        let id: UUID
        var warpID: UUID
        var content: String
        var status: Status
        var receivedAt: Date

        enum Status: String, Codable, Hashable {
            case pending, streaming, complete, error
        }

        init(id: UUID = UUID(),
             warpID: UUID,
             content: String = "",
             status: Status = .pending,
             receivedAt: Date = Date()) {
            self.id = id
            self.warpID = warpID
            self.content = content
            self.status = status
            self.receivedAt = receivedAt
        }
    }
}
