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
                let cmd: String
                if let path = project.localPath {
                    cmd = "cd \(path) && claude"
                } else if let repo = project.repo {
                    cmd = "cd ~/Nissan && gh repo clone \(repo) 2>/dev/null; cd ~/Nissan/\(project.name) && claude"
                } else {
                    cmd = "claude"
                }
                DeskfloorApp.openInITerm(cmd)
            }) {
                Label("Run Agent Session", systemImage: "play.fill")
            }

            Button(action: {
                if let path = project.localPath {
                    DeskfloorApp.openInITerm("cd \(path)")
                } else {
                    DeskfloorApp.sshJump(host: "hyle")
                }
            }) {
                Label("Open in iTerm", systemImage: "terminal")
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

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 86400 * 30 { return "\(Int(interval / 86400))d ago" }
        if interval < 86400 * 365 { return "\(Int(interval / (86400 * 30)))mo ago" }
        return "\(Int(interval / (86400 * 365)))y ago"
    }
}
