import Foundation
import os

/// Central observable data store. All background pollers write here.
/// All views read from here. Single source of truth.
@Observable
final class DataBus {
    // Fleet
    var fleetHosts: [String: HostSnapshot] = [:]
    var lastFleetPoll: Date?

    // Project health
    var projectAlerts: [AttentionItem] = []
    var ciStatuses: [String: CIRun] = [:]  // repo name → latest run
    var lastCIPoll: Date?

    // Attention — the merged, sorted view
    var attentionItems: [AttentionItem] = []

    // Polling state
    var isPolling = false
    private var pollTimer: Timer?
    private let agentSlackBase = ProcessInfo.processInfo.environment["AGENTSLACK_URL"] ?? "http://173.212.203.211:9400"

    struct HostSnapshot: Identifiable {
        var id: String { name }
        let name: String
        let sigil: String
        var load: Double
        var memPercent: Double
        var diskPercent: Int
        var claudeCount: Int
        var tmuxCount: Int
        var reachable: Bool
        var sessions: [String]
    }

    struct CIRun: Identifiable {
        var id: String { repo }
        let repo: String
        let status: CIStatus
        let conclusion: String?
        let branch: String
        let updatedAt: Date?
        let url: String?

        enum CIStatus: String {
            case completed, inProgress = "in_progress", queued, failure, unknown
        }
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
        Task.detached(priority: .utility) { @Sendable [weak self] in
            await self?.pollFleet()
            await self?.generateAlerts(projects: [])
        }
    }

    /// Full poll including project health analysis
    func poll(projects: [Project]) {
        let projectsCopy = projects  // capture Sendable copy
        Task.detached(priority: .utility) { @Sendable [weak self] in
            await self?.pollFleet()
            await self?.pollCI(projects: projectsCopy)
            await self?.generateAlerts(projects: projectsCopy)
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
            Logger.deskfloor.error("Fleet poll failed: \(error)")
        }
    }

    // MARK: - CI Polling (via gh CLI)

    private func pollCI(projects: [Project]) async {
        let repos = projects.compactMap(\.repo).filter { !$0.isEmpty }
        guard !repos.isEmpty else { return }

        // Concurrent polling, capped at 20 repos with 6 concurrent fetches
        let batch = Array(repos.prefix(20))
        let runs = await withTaskGroup(of: (String, CIRun)?.self, returning: [String: CIRun].self) { group in
            for repo in batch {
                group.addTask { [self] in
                    guard let run = await self.fetchLatestCIRun(repo: repo) else { return nil }
                    return (repo, run)
                }
            }
            var result: [String: CIRun] = [:]
            for await pair in group {
                if let (repo, run) = pair {
                    result[repo] = run
                }
            }
            return result
        }

        await MainActor.run {
            self.ciStatuses = runs
            self.lastCIPoll = Date()
            NSLog("[DataBus] CI polled \(runs.count) repos: \(runs.values.filter { $0.conclusion == "success" }.count) green, \(runs.values.filter { $0.conclusion == "failure" }.count) red")
        }
    }

    /// Write CI statuses back into a ProjectStore so cards can show badges.
    func syncCIToProjects(_ store: ProjectStore) {
        for i in store.projects.indices {
            guard let repo = store.projects[i].repo else { continue }
            if let run = ciStatuses[repo] {
                let badge: Project.CIBadge
                switch (run.status, run.conclusion) {
                case (.failure, _): badge = .red
                case (.completed, "success"): badge = .green
                case (.completed, "failure"): badge = .red
                case (.inProgress, _): badge = .yellow
                case (.queued, _): badge = .pending
                default: badge = .none
                }
                store.projects[i].ciStatus = badge
            }
        }
    }

    private static let iso8601 = ISO8601DateFormatter()

    private func fetchLatestCIRun(repo: String) async -> CIRun? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "run", "list", "-R", repo, "--limit", "1",
                                 "--json", "status,conclusion,headBranch,updatedAt,url"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      let raw = arr.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let statusStr = raw["status"] as? String ?? "unknown"
                let conclusion = raw["conclusion"] as? String
                let branch = raw["headBranch"] as? String ?? "?"
                let urlStr = raw["url"] as? String
                let updatedAt = (raw["updatedAt"] as? String).flatMap { Self.iso8601.date(from: $0) }

                let status: CIRun.CIStatus = (conclusion == "failure")
                    ? .failure
                    : CIRun.CIStatus(rawValue: statusStr) ?? .unknown

                continuation.resume(returning: CIRun(
                    repo: repo, status: status, conclusion: conclusion,
                    branch: branch, updatedAt: updatedAt, url: urlStr
                ))
            }
            do { try process.run() } catch { Logger.deskfloor.error("CI fetch failed: \(error)"); continuation.resume(returning: nil) }
        }
    }

    // MARK: - Alert Generation

    func generateAlerts(projects: [Project]) async {
        var alerts: [AttentionItem] = []

        // --- Fleet alerts ---
        for (_, host) in fleetHosts {
            if host.diskPercent >= 90 {
                alerts.append(AttentionItem(
                    severity: .critical,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) disk at \(host.diskPercent)%",
                    detail: "Disk is critically full. SSH in and clean up.",
                    actions: [.sshTo(host.name), .dispatch(context: "Disk cleanup on \(host.name): \(host.diskPercent)% full. Find large files and clean up.")]
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

            if host.load > 5 {
                alerts.append(AttentionItem(
                    severity: .warning,
                    source: "fleet:\(host.name)",
                    title: "\(host.sigil) \(host.name) load \(String(format: "%.1f", host.load))",
                    detail: "High load average. Check running processes.",
                    actions: [.sshTo(host.name)]
                ))
            }

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

        // --- CI alerts ---
        for (repo, run) in ciStatuses {
            if run.status == .failure || run.conclusion == "failure" {
                var actions: [AttentionItem.Action] = []
                if let urlStr = run.url, let url = URL(string: urlStr) {
                    actions.append(.openURL(url))
                }
                actions.append(.dispatch(context: "CI is failing on \(repo) (branch: \(run.branch)). Investigate and fix."))
                alerts.append(AttentionItem(
                    severity: .critical,
                    source: "ci:\(repo)",
                    title: "CI failing: \(repo.split(separator: "/").last ?? Substring(repo))",
                    detail: "Branch \(run.branch) — last run failed.",
                    actions: actions
                ))
            }
        }

        // --- Project health alerts ---
        let now = Date()
        for project in projects where project.status == .active {
            // Dirty files sitting uncommitted
            if let dirty = project.dirtyFiles, dirty > 5 {
                alerts.append(AttentionItem(
                    severity: .info,
                    source: "git:\(project.name)",
                    title: "\(project.name): \(dirty) dirty files",
                    detail: "Uncommitted changes piling up.",
                    actions: [.openProject(project.id)]
                ))
            }

            // Stale active project (no commits in 14+ days)
            if let lastActivity = project.lastActivity,
               now.timeIntervalSince(lastActivity) > 14 * 86400 {
                let days = Int(now.timeIntervalSince(lastActivity) / 86400)
                alerts.append(AttentionItem(
                    severity: .info,
                    source: "stale:\(project.name)",
                    title: "\(project.name): stale \(days)d",
                    detail: "Active project with no commits in \(days) days. Pause or push?",
                    actions: [.openProject(project.id)]
                ))
            }

            // Has encumbrances
            if !project.encumbrances.isEmpty {
                let kinds = project.encumbrances.map(\.kind.rawValue).joined(separator: ", ")
                alerts.append(AttentionItem(
                    severity: .warning,
                    source: "encumbrance:\(project.name)",
                    title: "\(project.name): blocked",
                    detail: "Encumbrances: \(kinds)",
                    actions: [.openProject(project.id)]
                ))
            }
        }

        // Sort: critical first, then warning, then info
        alerts.sort { $0.severity.rank < $1.severity.rank }

        // Preserve acknowledged state from previous poll
        let previousAcks = Set(self.attentionItems.filter(\.acknowledged).map(\.source))
        for i in alerts.indices where previousAcks.contains(alerts[i].source) {
            alerts[i].acknowledged = true
        }

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

    }

    enum Action {
        case sshTo(String)
        case openURL(URL)
        case runCommand(String, host: String?)
        case dispatch(context: String)
        case openProject(UUID)
    }
}
