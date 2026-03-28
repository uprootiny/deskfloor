import SwiftUI

/// "What needs my attention right now?" — sorted by severity, each item actionable.
struct AttentionView: View {
    @State var dataBus: DataBus

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                let critCount = dataBus.attentionItems.filter { $0.severity == .critical }.count
                let warnCount = dataBus.attentionItems.filter { $0.severity == .warning }.count

                if critCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("\(critCount) critical")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                if warnCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(warnCount) warning")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                if dataBus.attentionItems.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if let lastPoll = dataBus.lastFleetPoll {
                    Text(lastPoll, style: .relative)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }

                Button(action: { dataBus.poll() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.07, green: 0.07, blue: 0.09))

            Divider().opacity(0.2)

            if dataBus.attentionItems.isEmpty && dataBus.fleetHosts.isEmpty {
                // Not yet polled
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Polling fleet...")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { dataBus.startPolling() }
            } else if dataBus.attentionItems.isEmpty {
                // Polled, all clear
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.opacity(0.3))
                    Text("Fleet is healthy")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No alerts. All \(dataBus.fleetHosts.count) hosts reporting normally.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Alerts
                HSplitView {
                    alertList
                        .frame(minWidth: 400)
                    fleetOverview
                        .frame(minWidth: 300)
                }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear { dataBus.startPolling() }
    }

    // MARK: - Alert List

    private var alertList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(dataBus.attentionItems) { item in
                    AttentionItemRow(item: item)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Fleet Overview (right pane)

    private var fleetOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FLEET")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let sortedHosts = dataBus.fleetHosts.values
                        .sorted { a, b in
                            if a.name == "hyle" { return true }
                            if b.name == "hyle" { return false }
                            return a.name < b.name
                        }

                    ForEach(sortedHosts, id: \.name) { host in
                        FleetHostCard(host: host)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Attention Item Row

struct AttentionItemRow: View {
    let item: AttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Severity icon
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

                // Action buttons
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
        .background(item.severity == .critical ? item.severity.color.opacity(0.05) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func actionLabel(_ action: AttentionItem.Action) -> String {
        switch action {
        case .sshTo(let host): return "SSH to \(host)"
        case .openURL: return "Open"
        case .runCommand(let cmd, _): return "Run: \(cmd.prefix(20))"
        case .dispatch: return "Dispatch Agent"
        case .openProject: return "View Project"
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

// MARK: - Fleet Host Card

struct FleetHostCard: View {
    let host: DataBus.HostSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(host.sigil)
                    .font(.system(size: 14))
                Text(host.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Circle()
                    .fill(host.reachable ? .green : .red)
                    .frame(width: 6, height: 6)
            }

            // Metrics
            HStack(spacing: 12) {
                metricView("load", "\(String(format: "%.1f", host.load))",
                          color: host.load > 5 ? .red : host.load > 2 ? .orange : .green)
                metricView("disk", "\(host.diskPercent)%",
                          color: host.diskPercent >= 90 ? .red : host.diskPercent >= 80 ? .orange : .green)
                metricView("mem", "\(Int(host.memPercent))%",
                          color: host.memPercent > 80 ? .orange : .green)
                if host.claudeCount > 0 {
                    metricView("claude", "\(host.claudeCount)", color: .blue)
                }
                metricView("tmux", "\(host.tmuxCount)", color: .white.opacity(0.5))
            }

            // Sessions
            if !host.sessions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(host.sessions.prefix(6), id: \.self) { session in
                        Button(action: {
                            DeskfloorApp.sshJump(host: host.name, session: session)
                        }) {
                            Text(session)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .help("Attach \(session) on \(host.name)")
                    }
                    if host.sessions.count > 6 {
                        Text("+\(host.sessions.count - 6)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(host.diskPercent >= 90 ? .red.opacity(0.3) : .white.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button("SSH to \(host.name)") { DeskfloorApp.sshJump(host: host.name) }
            Button("Run Agent Session") {
                DeskfloorApp.dispatchToAgent(
                    context: "You are on \(host.name). Load: \(host.load), Disk: \(host.diskPercent)%, \(host.claudeCount) claude instances, \(host.tmuxCount) tmux sessions. Investigate and report status.",
                    workDir: nil
                )
            }
        }
    }

    private func metricView(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }
}
