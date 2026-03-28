import Foundation

@Observable
final class FrecencyTracker {
    private(set) var records: [String: FrecencyRecord] = [:]

    private let fileURL: URL

    struct FrecencyRecord: Codable {
        var itemID: String
        var count: Int
        var lastAccess: Date
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".deskfloor", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("frecency.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func recordAccess(itemID: String) {
        var record = records[itemID] ?? FrecencyRecord(itemID: itemID, count: 0, lastAccess: Date())
        record.count += 1
        record.lastAccess = Date()
        records[itemID] = record
        save()
    }

    func score(itemID: String) -> Double {
        guard let record = records[itemID] else { return 0 }
        let elapsed = Date().timeIntervalSince(record.lastAccess)
        let recencyWeight: Double
        switch elapsed {
        case ..<(6 * 3600):
            recencyWeight = 100
        case ..<(24 * 3600):
            recencyWeight = 80
        case ..<(3 * 24 * 3600):
            recencyWeight = 60
        case ..<(7 * 24 * 3600):
            recencyWeight = 40
        case ..<(30 * 24 * 3600):
            recencyWeight = 20
        default:
            recencyWeight = 10
        }
        return Double(record.count) * recencyWeight
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([FrecencyRecord].self, from: data)
            records = Dictionary(uniqueKeysWithValues: list.map { ($0.itemID, $0) })
        } catch {
            print("Failed to load frecency data: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Array(records.values))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save frecency data: \(error)")
        }
    }
}
