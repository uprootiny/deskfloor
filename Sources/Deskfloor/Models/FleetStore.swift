import Foundation

/// Live fleet data from AgentSlack API.
@Observable
final class FleetStore {
    var hosts: [FleetHost] = []
    var lastUpdate: Date?
    var isReachable = false

    private let baseURL = "http://173.212.203.211:9400"
    private var timer: Timer?

    struct FleetHost: Identifiable {
        let id: String
        let name: String
        let sigil: String
        var load: Double
        var memPercent: Double
        var diskPercent: Int
        var claudeCount: Int
        var tmuxCount: Int
        var reachable: Bool
        var sessions: [TmuxSession]
    }

    struct TmuxSession: Identifiable {
        let id: String
        let name: String
        var windows: Int
        var attached: Bool
    }

    static let sigils: [String: String] = [
        "hyle": "\u{1F702}",
        "finml": "\u{1F704}",
        "hub2": "\u{1F701}",
        "karlsruhe": "\u{1F703}",
        "nabla": "\u{2207}",
    ]

    func startPolling(interval: TimeInterval = 30) {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/fleet/metrics") else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let hostsDict = json?["hosts"] as? [String: [String: Any]] ?? [:]

                var newHosts: [FleetHost] = []
                for (name, raw) in hostsDict {
                    newHosts.append(FleetHost(
                        id: name,
                        name: name,
                        sigil: Self.sigils[name] ?? "",
                        load: raw["load_1"] as? Double ?? 0,
                        memPercent: raw["mem_pct"] as? Double ?? 0,
                        diskPercent: raw["disk_pct"] as? Int ?? 0,
                        claudeCount: raw["claude_count"] as? Int ?? 0,
                        tmuxCount: raw["tmux_count"] as? Int ?? 0,
                        reachable: raw["reachable"] as? Bool ?? false,
                        sessions: []
                    ))
                }

                // Fetch tmux sessions for hyle (the AgentSlack host)
                if let tmuxURL = URL(string: "\(baseURL)/tmux/sessions"),
                   let (tmuxData, _) = try? await URLSession.shared.data(from: tmuxURL),
                   let tmuxJSON = try? JSONSerialization.jsonObject(with: tmuxData) as? [[String: Any]] {
                    let sessions = tmuxJSON.map { raw in
                        TmuxSession(
                            id: raw["name"] as? String ?? UUID().uuidString,
                            name: raw["name"] as? String ?? "unknown",
                            windows: raw["windows"] as? Int ?? 1,
                            attached: raw["attached"] as? Bool ?? false
                        )
                    }
                    if let idx = newHosts.firstIndex(where: { $0.name == "hyle" }) {
                        newHosts[idx].sessions = sessions
                    }
                }

                // Sort: hyle first, then by name
                newHosts.sort { a, b in
                    if a.name == "hyle" { return true }
                    if b.name == "hyle" { return false }
                    return a.name < b.name
                }

                let finalHosts = newHosts
                await MainActor.run {
                    self.hosts = finalHosts
                    self.lastUpdate = Date()
                    self.isReachable = true
                    NSLog("[FleetStore] Polled \(finalHosts.count) hosts")
                }
            } catch {
                NSLog("[FleetStore] Poll failed: \(error)")
                await MainActor.run {
                    self.isReachable = false
                }
            }
        }
    }
}
