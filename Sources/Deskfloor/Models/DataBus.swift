import Foundation

/// Central observable data store. All background pollers write here.
/// All views read from here. Single source of truth.
@Observable
final class DataBus {
    // Fleet
    var fleetHosts: [String: HostSnapshot] = [:]
    var fleetAlerts: [AttentionItem] = []
    var lastFleetPoll: Date?

    // Attention — the key abstraction
    var attentionItems: [AttentionItem] = []

    // Polling state
    var isPolling = false
    private var pollTimer: Timer?
    private let agentSlackBase = "http://173.212.203.211:9400"

    struct HostSnapshot {
        let name: String
        let sigil: String
        var load: Double
        var memPercent: Double
        var diskPercent: Int
        var claudeCount: Int
        var tmuxCount: Int
        var reachable: Bool
        var sessions: [String] // tmux session names
    }

    // MARK: - Polling

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    func poll() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.pollFleet()
            await self?.generateAlerts()
        }
    }

    // MARK: - Fleet Polling

    private func pollFleet() async {
        guard let url = URL(string: "\(agentSlackBase)/fleet/metrics") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let hostsDict = json?["hosts"] as? [String: [String: Any]] ?? [:]

            let sigils: [String: String] = [
                "hyle": "\u{1F702}", "finml": "\u{1F704}", "hub2": "\u{1F701}",
                "karlsruhe": "\u{1F703}", "nabla": "\u{2207}", "gcp1": "\u{2601}"
            ]

            var snapshots: [String: HostSnapshot] = [:]
            for (name, raw) in hostsDict {
                snapshots[name] = HostSnapshot(
                    name: name,
                    sigil: sigils[name] ?? "?",
                    load: raw["load_1"] as? Double ?? 0,
                    memPercent: raw["mem_pct"] as? Double ?? 0,
                    diskPercent: raw["disk_pct"] as? Int ?? 0,
                    claudeCount: raw["claude_count"] as? Int ?? 0,
                    tmuxCount: raw["tmux_count"] as? Int ?? 0,
                    reachable: raw["reachable"] as? Bool ?? false,
                    sessions: []
                )
            }

            // Fetch tmux sessions for hyle
            if let tmuxURL = URL(string: "\(agentSlackBase)/tmux/sessions"),
               let (tmuxData, _) = try? await URLSession.shared.data(from: tmuxURL),
               let tmuxJSON = try? JSONSerialization.jsonObject(with: tmuxData) as? [[String: Any]] {
                let sessionNames = tmuxJSON.compactMap { $0["name"] as? String }
                snapshots["hyle"]?.sessions = sessionNames
            }

            await MainActor.run {
                self.fleetHosts = snapshots
                self.lastFleetPoll = Date()
            }
        } catch {
            // Fleet unreachable — don't clear existing data
        }
    }

    // MARK: - Alert Generation

    private func generateAlerts() async {
        var alerts: [AttentionItem] = []

        for (_, host) in fleetHosts {
            // Disk critical
            if host.diskPercent >= 90 {
                alerts.append(AttentionItem(
                    severity: .critical,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) disk at \(host.diskPercent)%",
                    detail: "Disk is critically full. SSH in and clean up.",
                    actions: [.sshTo(host.name)]
                ))
            } else if host.diskPercent >= 80 {
                alerts.append(AttentionItem(
                    severity: .warning,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) disk at \(host.diskPercent)%",
                    detail: "Disk is filling up.",
                    actions: [.sshTo(host.name)]
                ))
            }

            // High load
            if host.load > 5 {
                alerts.append(AttentionItem(
                    severity: .warning,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) load \(String(format: "%.1f", host.load))",
                    detail: "High load average. Check running processes.",
                    actions: [.sshTo(host.name)]
                ))
            }

            // Unreachable
            if !host.reachable {
                alerts.append(AttentionItem(
                    severity: .critical,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) unreachable",
                    detail: "Host is not responding to fleet metrics poll.",
                    actions: [.sshTo(host.name)]
                ))
            }
        }

        // Sort: critical first, then warning, then info
        alerts.sort { $0.severity.rank < $1.severity.rank }

        await MainActor.run {
            self.attentionItems = alerts
        }
    }
}

// MARK: - AttentionItem

struct AttentionItem: Identifiable {
    let id = UUID()
    let severity: Severity
    let source: String
    let title: String
    let detail: String
    let actions: [Action]
    let detectedAt = Date()
    var acknowledged = false

    enum Severity: String {
        case critical, warning, info

        var rank: Int {
            switch self {
            case .critical: 0
            case .warning: 1
            case .info: 2
            }
        }

        var icon: String {
            switch self {
            case .critical: "exclamationmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .critical: .red
            case .warning: .orange
            case .info: .blue
            }
        }
    }

    enum Action {
        case sshTo(String)
        case openURL(URL)
        case runCommand(String, host: String?)
        case dispatch(context: String)
        case openProject(UUID)
    }
}

import SwiftUI
