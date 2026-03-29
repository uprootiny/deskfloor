import SwiftUI

/// "What needs my attention right now?" — sorted by severity, each item actionable.
/// Left: alert list. Right: fleet topology + project health summary.
struct AttentionView: View {
    @State var dataBus: DataBus
    var store: ProjectStore?
    @State private var selectedSource: String?
    @State private var filter: AlertFilter = .all

    enum AlertFilter: String, CaseIterable {
        case all = "All"
        case fleet = "Fleet"
        case ci = "CI"
        case project = "Projects"

        func matches(_ source: String) -> Bool {
            switch self {
            case .all: true
            case .fleet: source.hasPrefix("fleet:")
            case .ci: source.hasPrefix("ci:")
            case .project: source.hasPrefix("git:") || source.hasPrefix("stale:") || source.hasPrefix("encumbrance:")
            }
        }
    }

    private var filteredItems: [AttentionItem] {
        dataBus.attentionItems.filter { filter.matches($0.source) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().opacity(0.2)

            if dataBus.attentionItems.isEmpty && dataBus.fleetHosts.isEmpty {
                loadingState
            } else {
                HSplitView {
                    alertPanel
                        .frame(minWidth: 420)
                    rightPanel
                        .frame(minWidth: 340)
                }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            dataBus.startPolling()
            if let projects = store?.projects {
                dataBus.poll(projects: projects)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Severity counts
            let critCount = dataBus.attentionItems.filter { $0.severity == .critical }.count
            let warnCount = dataBus.attentionItems.filter { $0.severity == .warning }.count
            let infoCount = dataBus.attentionItems.filter { $0.severity == .info }.count

            if critCount > 0 {
                severityPill(count: critCount, label: "critical", color: .red, icon: "exclamationmark.octagon.fill")
            }
            if warnCount > 0 {
                severityPill(count: warnCount, label: "warning", color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if infoCount > 0 {
                severityPill(count: infoCount, label: "info", color: .blue, icon: "info.circle.fill")
            }
            if dataBus.attentionItems.isEmpty && !dataBus.fleetHosts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            // Filter chips
            HStack(spacing: 2) {
                ForEach(AlertFilter.allCases, id: \.rawValue) { f in
                    Button(action: { filter = f }) {
                        Text(f.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(filter == f ? .white : .white.opacity(0.3))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(filter == f ? .white.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let lastPoll = dataBus.lastFleetPoll {
                Text(lastPoll, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            Button(action: {
                if let projects = store?.projects {
                    dataBus.poll(projects: projects)
                } else {
                    dataBus.poll()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    private func severityPill(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Polling fleet...")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dataBus.startPolling() }
    }

    // MARK: - Alert Panel (left)

    private var alertPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.opacity(0.3))
                    Text(filter == .all ? "Fleet is healthy" : "No \(filter.rawValue.lowercased()) alerts")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredItems) { item in
                            AttentionItemRow(
                                item: item,
                                isSelected: selectedSource == item.source,
                                onTap: { selectedSource = item.source }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Right Panel (topology + summary)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fleet topology
            fleetTopology
                .frame(minHeight: 200)

            Divider().opacity(0.15)

            // Summary stats
            summaryStats
        }
    }

    // MARK: - Fleet Topology

    private var fleetTopology: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FLEET TOPOLOGY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text("\(dataBus.fleetHosts.count) hosts")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            GeometryReader { geo in
                let hosts = sortedHosts
                let cols = hosts.count <= 3 ? hosts.count : (hosts.count + 1) / 2
                let rows = hosts.count <= 3 ? 1 : 2
                let cellW = geo.size.width / CGFloat(max(cols, 1))
                let cellH = geo.size.height / CGFloat(rows)

                ZStack {
                    // Connection lines between hosts
                    ForEach(Array(hosts.enumerated()), id: \.element.name) { i, _ in
                        ForEach(Array(hosts.enumerated()), id: \.element.name) { j, _ in
                            if j > i {
                                let p1 = hostPosition(index: i, cols: cols, cellW: cellW, cellH: cellH)
                                let p2 = hostPosition(index: j, cols: cols, cellW: cellW, cellH: cellH)
                                Path { path in
                                    path.move(to: p1)
                                    path.addLine(to: p2)
                                }
                                .stroke(.white.opacity(0.04), lineWidth: 1)
                            }
                        }
                    }

                    // Host nodes
                    ForEach(Array(hosts.enumerated()), id: \.element.name) { i, host in
                        let pos = hostPosition(index: i, cols: cols, cellW: cellW, cellH: cellH)
                        FleetNode(host: host, hasAlert: hostHasAlert(host.name))
                            .position(pos)
                            .onTapGesture { DeskfloorApp.sshJump(host: host.name) }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var sortedHosts: [DataBus.HostSnapshot] {
        dataBus.fleetHosts.values.sorted { a, b in
            if a.name == "hyle" { return true }
            if b.name == "hyle" { return false }
            return a.name < b.name
        }
    }

    private func hostPosition(index: Int, cols: Int, cellW: CGFloat, cellH: CGFloat) -> CGPoint {
        let row = index / cols
        let col = index % cols
        return CGPoint(
            x: cellW * CGFloat(col) + cellW / 2,
            y: cellH * CGFloat(row) + cellH / 2
        )
    }

    private func hostHasAlert(_ name: String) -> Bool {
        dataBus.attentionItems.contains { $0.source == "fleet:\(name)" }
    }

    // MARK: - Summary Stats

    private var summaryStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // Fleet summary
                    let totalClaude = dataBus.fleetHosts.values.reduce(0) { $0 + $1.claudeCount }
                    let totalTmux = dataBus.fleetHosts.values.reduce(0) { $0 + $1.tmuxCount }
                    let reachable = dataBus.fleetHosts.values.filter(\.reachable).count

                    statRow("Hosts online", "\(reachable)/\(dataBus.fleetHosts.count)",
                            color: reachable == dataBus.fleetHosts.count ? .green : .orange)
                    statRow("Claude sessions", "\(totalClaude)", color: .blue)
                    statRow("Tmux sessions", "\(totalTmux)", color: .white.opacity(0.6))

                    Divider().opacity(0.1).padding(.vertical, 4)

                    // CI summary
                    if !dataBus.ciStatuses.isEmpty {
                        let failing = dataBus.ciStatuses.values.filter { $0.status == .failure || $0.conclusion == "failure" }.count
                        let passing = dataBus.ciStatuses.values.filter { $0.conclusion == "success" }.count

                        statRow("CI passing", "\(passing)", color: .green)
                        if failing > 0 {
                            statRow("CI failing", "\(failing)", color: .red)
                        }

                        Divider().opacity(0.1).padding(.vertical, 4)
                    }

                    // Project summary
                    if let projects = store?.projects {
                        let active = projects.filter { $0.status == .active }.count
                        let dirty = projects.filter { ($0.dirtyFiles ?? 0) > 0 }.count
                        let encumbered = projects.filter { !$0.encumbrances.isEmpty }.count

                        statRow("Active projects", "\(active)", color: .green)
                        if dirty > 0 {
                            statRow("With uncommitted", "\(dirty)", color: .orange)
                        }
                        if encumbered > 0 {
                            statRow("Blocked", "\(encumbered)", color: .red)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Fleet Node (topology visualization)

struct FleetNode: View {
    let host: DataBus.HostSnapshot
    let hasAlert: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer ring: health color
                Circle()
                    .stroke(ringColor, lineWidth: 2)
                    .frame(width: 52, height: 52)

                // Alert pulse
                if hasAlert {
                    Circle()
                        .stroke(ringColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 60, height: 60)
                }

                // Inner circle
                Circle()
                    .fill(ringColor.opacity(0.1))
                    .frame(width: 48, height: 48)

                // Content
                VStack(spacing: 1) {
                    Text(host.sigil)
                        .font(.system(size: 16))
                    if host.claudeCount > 0 {
                        Text("\(host.claudeCount)cl")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }
            }

            Text(host.name)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            // Metric bar
            HStack(spacing: 6) {
                miniMetric(host.load, threshold: 5, format: "%.0f")
                miniMetric(Double(host.diskPercent), threshold: 85, format: "%.0f%%")
            }
        }
        .help("Click to SSH to \(host.name)\nLoad: \(String(format: "%.1f", host.load)) | Disk: \(host.diskPercent)% | Mem: \(Int(host.memPercent))%")
    }

    private var ringColor: Color {
        if !host.reachable { return .red }
        if host.diskPercent >= 90 || host.load > 8 { return .red }
        if host.diskPercent >= 80 || host.load > 5 { return .orange }
        return .green
    }

    private func miniMetric(_ value: Double, threshold: Double, format: String) -> some View {
        Text(String(format: format, value))
            .font(.system(size: 7, design: .monospaced))
            .foregroundStyle(value >= threshold ? .orange : .white.opacity(0.3))
    }
}

// MARK: - Attention Item Row

struct AttentionItemRow: View {
    let item: AttentionItem
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.severity.icon)
                .font(.system(size: 14))
                .foregroundStyle(item.severity.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 8) {
                    ForEach(Array(item.actions.enumerated()), id: \.0) { _, action in
                        Button(action: { executeAction(action) }) {
                            Text(actionLabel(action))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(item.severity.color.opacity(0.15))
                        .foregroundStyle(item.severity.color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Spacer()

            Text(item.detectedAt, style: .relative)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? item.severity.color.opacity(0.08) :
                      item.severity == .critical ? item.severity.color.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func actionLabel(_ action: AttentionItem.Action) -> String {
        switch action {
        case .sshTo(let host): "SSH \(host)"
        case .openURL: "Open"
        case .runCommand(let cmd, _): "Run: \(cmd.prefix(20))"
        case .dispatch: "Dispatch Agent"
        case .openProject: "View Project"
        }
    }

    private func executeAction(_ action: AttentionItem.Action) {
        switch action {
        case .sshTo(let host):
            DeskfloorApp.sshJump(host: host)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .runCommand(let cmd, let host):
            if let host {
                DeskfloorApp.openInITerm("ssh -o RemoteCommand=none \(host) '\(cmd)'")
            } else {
                DeskfloorApp.openInITerm(cmd)
            }
        case .dispatch(let context):
            DeskfloorApp.dispatchToAgent(context: context)
        case .openProject:
            break // TODO: navigate to project
        }
    }
}
