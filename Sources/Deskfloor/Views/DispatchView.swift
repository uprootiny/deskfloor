import SwiftUI
import AppKit

/// Panel for dispatching selected projects to an LLM agent (Claude Code, etc.)
struct DispatchView: View {
    let projects: [Project]
    var onDismiss: () -> Void

    @State private var prompt = ""
    @State private var includeGitInfo = true
    @State private var includeConnections = true
    @State private var dispatched = false

    private var context: String {
        var parts: [String] = []
        parts.append("## Context: \(projects.count) project\(projects.count == 1 ? "" : "s")\n")

        for project in projects {
            var lines: [String] = []
            lines.append("### \(project.name)")
            if let repo = project.repo { lines.append("Repo: \(repo)") }
            if !project.description.isEmpty { lines.append("Description: \(project.description)") }
            lines.append("Status: \(project.status.label) · Perspective: \(project.perspective.label)")
            if !project.tags.isEmpty { lines.append("Tags: \(project.tags.joined(separator: ", "))") }

            if includeGitInfo {
                if let branch = project.gitBranch { lines.append("Branch: \(branch)") }
                if let dirty = project.dirtyFiles, dirty > 0 { lines.append("Dirty files: \(dirty)") }
                if project.commitCount > 0 { lines.append("Commits: \(project.commitCount)") }
                if let msg = project.lastCommitMessage { lines.append("Last commit: \(msg)") }
                if let path = project.localPath { lines.append("Local: \(path)") }
            }

            if includeConnections && !project.connections.isEmpty {
                lines.append("Connected to: \(project.connections.joined(separator: ", "))")
            }

            parts.append(lines.joined(separator: "\n"))
        }

        if !prompt.isEmpty {
            parts.append("\n## Task\n\(prompt)")
        }

        return parts.joined(separator: "\n\n")
    }

    private var tokenEstimate: Int { context.count / 4 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dispatch to Agent")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding()

            Divider().opacity(0.2)

            // Project list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(projects) { project in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(project.status.color)
                                .frame(width: 6, height: 6)
                            Text(project.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            if let lang = project.tags.first {
                                Text(lang)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            // Options
            HStack(spacing: 16) {
                Toggle("Include git info", isOn: $includeGitInfo)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Toggle("Include connections", isOn: $includeConnections)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Spacer()
                Text("~\(tokenEstimate) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider().opacity(0.2)

            // Prompt field
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR PROMPT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minHeight: 80, maxHeight: 150)
            }
            .padding()

            Divider().opacity(0.2)

            // Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTEXT PREVIEW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                ScrollView {
                    Text(context)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider().opacity(0.2)

            // Actions
            HStack(spacing: 12) {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(context, forType: .string)
                    dispatched = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onDismiss() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))

                Button("Open in iTerm + Claude Code") {
                    DeskfloorApp.dispatchToAgent(context: context)
                    dispatched = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onDismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue.opacity(0.8))

                Spacer()

                if dispatched {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied!")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 11))
                }
            }
            .padding()
        }
        .frame(width: 640, height: 600)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }
}
