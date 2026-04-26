import SwiftUI

struct ProjectCard: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project
    var isSelected: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        DfCard(isSelected: isSelected, accentColor: project.perspective.color) {
            VStack(alignment: .leading, spacing: Df.space1) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Df.textPrimary(scheme))
                        .lineLimit(1)

                    Spacer()

                    // CI badge — clickable, opens GitHub Actions for the repo
                    if let ci = project.ciStatus, ci != .none, let repo = project.repo {
                        Button {
                            if let url = URL(string: "https://github.com/\(repo)/actions") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Image(systemName: ciIconName(ci))
                                .font(.system(size: 10))
                                .foregroundStyle(ciIconColor(ci))
                        }
                        .buttonStyle(.plain)
                        .help("CI \(ci.rawValue) — click to open GitHub Actions")
                    }

                    // Stale indicator — active project untouched for > 30 days
                    if isStale {
                        Text("stale")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Df.uncertain)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Df.uncertain.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .help("Active but no commits in 30+ days — consider Pause / Archive")
                    }

                    perspectiveBadge

                    if let repo = project.repo {
                        Button(action: {
                            if let url = URL(string: "https://github.com/\(repo)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                        .buttonStyle(.plain)
                        .help("Open on GitHub")
                    }
                }

                if !project.description.isEmpty {
                    Text(project.description)
                        .font(Df.captionFont)
                        .foregroundStyle(Df.textSecondary(scheme))
                        .lineLimit(1)
                }

                // Git info row
                if let branch = project.gitBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                            .foregroundStyle(Df.textTertiary(scheme))
                        Text(branch)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textSecondary(scheme))
                            .lineLimit(1)
                        if let dirty = project.dirtyFiles, dirty > 0 {
                            DfPill(text: "\(dirty) changed", color: Df.tentative)
                        }
                        if project.commitCount > 0 {
                            Text("\(project.commitCount) commits")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                        Spacer()
                    }
                }

                HStack(spacing: 6) {
                    if let lastActivity = project.lastActivity {
                        Text(relativeDate(lastActivity))
                            .font(Df.monoFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }

                    if let type = project.projectType ?? project.tags.first, !type.isEmpty {
                        DfPill(text: type, color: languageColor(type))
                    }

                    Spacer()

                    encumbranceDots
                }
            }
            .padding(Df.space2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: {
                if let path = project.localPath {
                    TerminalLauncher.run("claude", in: path)
                } else if let repo = project.repo {
                    let nissan = NSString(string: "~/Nissan").expandingTildeInPath
                    TerminalLauncher.run("gh repo clone \(Sh.q(repo)) 2>/dev/null; cd \(Sh.q(project.name)) && claude", in: nissan)
                }
            }) {
                Label("Run Agent Session", systemImage: "play.fill")
            }

            Button(action: {
                if let path = project.localPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }) {
                Label("Reveal in Finder", systemImage: "folder")
            }

            if let repo = project.repo {
                Button(action: {
                    if let url = URL(string: "https://github.com/\(repo)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Open on GitHub", systemImage: "link")
                }
            }

            Divider()

            Menu("Set Status") {
                ForEach(Status.allCases) { status in
                    Button(status.label) {
                        NotificationCenter.default.post(
                            name: .projectStatusChange,
                            object: nil,
                            userInfo: ["id": project.id, "status": status]
                        )
                    }
                }
            }
        }
    }

    private var perspectiveBadge: some View {
        Text(project.perspective.label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(project.perspective.color.opacity(scheme == .dark ? 0.25 : 0.15))
            .foregroundStyle(project.perspective.color)
            .clipShape(Capsule())
    }

    private var encumbranceDots: some View {
        HStack(spacing: 3) {
            let kinds = Set(project.encumbrances.map(\.kind))
            ForEach(Array(kinds).sorted(by: { $0.rawValue < $1.rawValue })) { kind in
                Circle()
                    .fill(kind.dotColor)
                    .frame(width: 6, height: 6)
                    .help(kind.label)
            }
            if project.handoffReady {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Df.certain)
                    .help("Handoff ready")
            }
        }
    }

    private func languageColor(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "swift": return Color(red: 1.0, green: 0.6, blue: 0.2)
        case "rust": return Color(red: 0.87, green: 0.4, blue: 0.2)
        case "clojure": return Color(red: 0.4, green: 0.7, blue: 0.2)
        case "haskell": return Color(red: 0.6, green: 0.4, blue: 0.8)
        case "elixir": return Color(red: 0.5, green: 0.3, blue: 0.7)
        case "typescript", "javascript": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "python": return Color(red: 0.3, green: 0.6, blue: 0.8)
        case "html", "css": return Color(red: 0.9, green: 0.4, blue: 0.2)
        case "shell": return Color(red: 0.5, green: 0.7, blue: 0.5)
        case "c++", "c": return Color(red: 0.4, green: 0.5, blue: 0.8)
        default: return Df.textSecondary(.dark)
        }
    }

    private var isStale: Bool {
        guard project.status == .active,
              let last = project.lastActivity else { return false }
        return Date().timeIntervalSince(last) > 30 * 86400
    }

    private func ciIconName(_ ci: Project.CIBadge) -> String {
        switch ci {
        case .green: return "checkmark.circle.fill"
        case .red: return "xmark.circle.fill"
        case .yellow: return "clock.circle.fill"
        case .pending: return "circle.dotted"
        case .none: return "circle"
        }
    }

    private func ciIconColor(_ ci: Project.CIBadge) -> Color {
        switch ci {
        case .green: return .green
        case .red: return .red
        case .yellow: return .yellow
        case .pending: return .white.opacity(0.3)
        case .none: return .clear
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 86400 * 30 { return "\(Int(interval / 86400))d ago" }
        if interval < 86400 * 365 { return "\(Int(interval / (86400 * 30)))mo ago" }
        return "\(Int(interval / (86400 * 365)))y ago"
    }
}
