import SwiftUI

struct ProjectCard: View {
    let project: Project
    var onTap: () -> Void = {}

    private let monoFont = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
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
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Open on GitHub")
                }
            }

            if !project.description.isEmpty {
                Text(project.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let lastActivity = project.lastActivity {
                    Text(relativeDate(lastActivity))
                        .font(monoFont)
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Language tag
                if let lang = project.tags.first, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(languageColor(lang).opacity(0.2))
                        .foregroundStyle(languageColor(lang))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                encumbranceDots
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var perspectiveBadge: some View {
        Text(project.perspective.label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(project.perspective.color.opacity(0.25))
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
                    .foregroundStyle(Color(red: 0.3, green: 0.7, blue: 0.5))
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
        default: return .white.opacity(0.5)
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
