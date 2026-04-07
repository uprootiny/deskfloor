import SwiftUI

struct ProjectDeploySection: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var expandedSections: Binding<Set<String>>
    var fleet: FleetStore?
    var dataBus: DataBus?
    @Binding var showDeployConfig: Bool

    private var hasDeploy: Bool { project.deployHost != nil }
    private var hasLiveURL: Bool { project.deployURL != nil }

    private var deployHostInfo: FleetStore.FleetHost? {
        guard let fleet, let host = project.deployHost else { return nil }
        return fleet.hosts.first { $0.name == host }
    }

    private var ciRun: DataBus.CIRun? {
        guard let dataBus, let repo = project.repo else { return nil }
        let name = repo.components(separatedBy: "/").last ?? repo
        return dataBus.ciStatuses[name] ?? dataBus.ciStatuses[repo]
    }

    var body: some View {
        ProjectActionSection(title: "DEPLOY & OPS", icon: "server.rack", key: "deploy", expandedSections: expandedSections, project: $project) {
            VStack(alignment: .leading, spacing: Df.space2) {
                actionButtons
                statusRow
                deployConfig
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Df.space2) {
            if hasDeploy, let cmd = project.deployCommand {
                ProjectActionBtn("paperplane.fill", "Deploy", .accent) {
                    let host = project.deployHost!
                    let remote = project.deployPath.map { "cd \($0) && " } ?? ""
                    DeskfloorApp.openInITerm("ssh \(host) '\(remote)\(cmd)'")
                }
            } else {
                ProjectDisabledAction("paperplane.fill", "Deploy", hint: hasDeploy ? "set command" : "configure below")
            }

            if let url = project.deployURL {
                ProjectActionBtn("globe", "Live", .primary) {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
            } else {
                ProjectDisabledAction("globe", "Live", hint: "set URL")
            }

            if let hostInfo = deployHostInfo {
                ProjectActionBtn("cpu", "Server", .secondary) {
                    DeskfloorApp.sshJump(host: hostInfo.name)
                }
            } else if hasDeploy {
                ProjectActionBtn("cpu", "Server", .secondary) {
                    DeskfloorApp.sshJump(host: project.deployHost!)
                }
            } else {
                ProjectDisabledAction("cpu", "Server", hint: "set host")
            }

            if hasDeploy {
                ProjectActionBtn("doc.text.magnifyingglass", "Logs", .secondary) {
                    let host = project.deployHost!
                    let path = project.deployPath ?? "~"
                    DeskfloorApp.openInITerm("ssh \(host) 'cd \(path) && tail -100f *.log 2>/dev/null || journalctl -n 100 -f'")
                }
            } else {
                ProjectDisabledAction("doc.text.magnifyingglass", "Logs", hint: "set host")
            }

            Spacer()
        }
    }

    private var statusRow: some View {
        HStack(spacing: Df.space4) {
            if let hostInfo = deployHostInfo {
                HStack(spacing: 3) {
                    Text(hostInfo.sigil).font(.system(size: 10))
                    Text(hostInfo.name).font(Df.monoSmallFont).foregroundStyle(Df.textSecondary(scheme))
                    DfPill(
                        text: String(format: "%.0f", hostInfo.load),
                        color: hostInfo.load > 4 ? Df.critical : hostInfo.load > 2 ? Df.uncertain : Df.certain
                    )
                    DfPill(
                        text: "\(hostInfo.diskPercent)%",
                        color: hostInfo.diskPercent >= 85 ? Df.uncertain : Df.certain
                    )
                }
            }

            if let ci = ciRun {
                HStack(spacing: 3) {
                    Image(systemName: ci.status == .completed && ci.conclusion == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ci.conclusion == "success" ? Df.certain : Df.critical)
                    Text("CI \(ci.conclusion ?? ci.status.rawValue)")
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textSecondary(scheme))
                    if let url = ci.url {
                        Button {
                            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 8))
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var deployConfig: some View {
        if !hasDeploy || showDeployConfig {
            deployConfigFields
        }

        if !hasDeploy && !showDeployConfig {
            Button {
                showDeployConfig = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape").font(.system(size: 9))
                    Text("Configure deployment").font(Df.monoSmallFont)
                }
                .foregroundStyle(Df.textTertiary(scheme))
            }
            .buttonStyle(.plain)
        }
    }

    private var deployConfigFields: some View {
        VStack(alignment: .leading, spacing: Df.space1) {
            HStack(spacing: Df.space2) {
                configField("Host", binding: Binding(
                    get: { project.deployHost ?? "" },
                    set: { project.deployHost = $0.isEmpty ? nil : $0 }
                ), placeholder: "e.g. hyle")

                configField("Path", binding: Binding(
                    get: { project.deployPath ?? "" },
                    set: { project.deployPath = $0.isEmpty ? nil : $0 }
                ), placeholder: "e.g. /opt/myapp")
            }
            HStack(spacing: Df.space2) {
                configField("Command", binding: Binding(
                    get: { project.deployCommand ?? "" },
                    set: { project.deployCommand = $0.isEmpty ? nil : $0 }
                ), placeholder: "e.g. docker compose up -d")

                configField("URL", binding: Binding(
                    get: { project.deployURL ?? "" },
                    set: { project.deployURL = $0.isEmpty ? nil : $0 }
                ), placeholder: "e.g. https://...")
            }
        }
        .padding(Df.space2)
        .background(Df.inset(scheme).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
    }

    private func configField(_ label: String, binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Df.microFont).foregroundStyle(Df.textQuaternary(scheme))
            TextField(placeholder, text: binding)
                .font(Df.monoSmallFont)
                .textFieldStyle(.plain)
                .foregroundStyle(Df.textPrimary(scheme))
        }
        .frame(maxWidth: .infinity)
    }
}
