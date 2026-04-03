import SwiftUI

// MARK: - Project Detail Sheet
//
// Design intent:
// - Hero: identity at a glance — name, status, perspective, description
// - Actions: capability-aware panels that show what's possible and what's missing
//   - SOURCE: open code, editor, GitHub
//   - AGENT: resume/fresh/history — linked to skein threads
//   - DEPLOY & OPS: deploy, live view, server state, logs — linked to fleet+CI
//   - GIT: branch, dirty, commits, last message
// - Each action section folds/unfolds. Unavailable actions show dimmed with a
//   one-word hint ("needs repo", "set deploy host") so the user knows how to enable them.
// - Progress notes + tags are secondary, below the fold.

struct ProjectDetailSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var isNew: Bool = false
    var skein: SkeinStore? = nil
    var fleet: FleetStore? = nil
    var dataBus: DataBus? = nil
    var onSave: (Project) -> Void
    var onDelete: (() -> Void)?
    var onCancel: () -> Void

    @State private var newTag = ""
    @State private var newConnection = ""
    @State private var newNoteText = ""
    @State private var newEncKind: EncumbranceKind = .dependency
    @State private var newEncDesc = ""
    @State private var editingDescription = false
    @State private var confirmDelete = false
    @State private var showDeployConfig = false
    @State private var expandedSections: Set<String> = ["source", "agent"]

    // Derived state
    private var agentThreads: [Thread] {
        guard let skein else { return [] }
        return skein.threadsForProject(project.id)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var ciRun: DataBus.CIRun? {
        guard let dataBus, let repo = project.repo else { return nil }
        let name = repo.components(separatedBy: "/").last ?? repo
        return dataBus.ciStatuses[name] ?? dataBus.ciStatuses[repo]
    }

    private var deployHostInfo: FleetStore.FleetHost? {
        guard let fleet, let host = project.deployHost else { return nil }
        return fleet.hosts.first { $0.name == host }
    }

    private var hasSource: Bool { project.localPath != nil }
    private var hasRepo: Bool { project.repo != nil }
    private var hasDeploy: Bool { project.deployHost != nil }
    private var hasLiveURL: Bool { project.deployURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            heroBar
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Df.space4) {
                    sourceSection
                    agentSection
                    deploySection
                    gitCard
                    progressBlock
                    if !project.tags.isEmpty || !project.connections.isEmpty || isNew {
                        tagsAndConnections
                    }
                    if !project.encumbrances.isEmpty {
                        encumbranceList
                    }
                    if !project.why.isEmpty || isNew {
                        whyBlock
                    }
                }
                .padding(Df.space4)
            }

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 500)
        .frame(minHeight: 480, maxHeight: 680)
        .background(Df.canvas(scheme))
        .alert("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Hero

    private var heroBar: some View {
        VStack(alignment: .leading, spacing: Df.space2) {
            HStack(alignment: .top, spacing: Df.space3) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(project.perspective.color)
                    .frame(width: 4, height: 30)
                    .shadow(color: project.perspective.color.opacity(0.4), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    if isNew {
                        TextField("Project name", text: $project.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .textFieldStyle(.plain)
                    } else {
                        Text(project.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Df.textPrimary(scheme))
                    }
                    // Inline editable description
                    if editingDescription || project.description.isEmpty {
                        TextField("What is this?", text: $project.description)
                            .font(Df.bodyFont)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Df.textSecondary(scheme))
                            .onSubmit { editingDescription = false }
                    } else {
                        Text(project.description)
                            .font(Df.bodyFont)
                            .foregroundStyle(Df.textSecondary(scheme))
                            .lineLimit(2)
                            .onTapGesture { editingDescription = true }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    chipMenu(project.status.label, color: project.status.color) {
                        ForEach(Status.allCases) { s in
                            Button { project.status = s } label: {
                                HStack { Circle().fill(s.color).frame(width: 8, height: 8); Text(s.label) }
                            }
                        }
                    }
                    chipMenu(project.perspective.label, color: project.perspective.color) {
                        ForEach(Perspective.allCases) { p in
                            Button { project.perspective = p } label: {
                                HStack { Circle().fill(p.color).frame(width: 8, height: 8); Text(p.label) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space3)
        .background(Df.surface(scheme))
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        actionSection("SOURCE", icon: "doc.text", key: "source") {
            HStack(spacing: Df.space2) {
                if hasSource {
                    actionBtn("folder", "Open", .primary) {
                        DeskfloorApp.openInITerm("cd \(project.localPath!)")
                    }
                } else {
                    disabledAction("folder", "Open", hint: "needs local path")
                }

                if hasRepo {
                    actionBtn("link", "GitHub", .secondary) {
                        if let url = URL(string: "https://github.com/\(project.repo!)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    disabledAction("link", "GitHub", hint: "set repo")
                }

                if hasRepo {
                    actionBtn("arrow.down.circle", "Clone", .secondary) {
                        DeskfloorApp.openInITerm("cd ~/Nissan && gh repo clone \(project.repo!)")
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Agent Section

    private var agentSection: some View {
        actionSection("AGENT", icon: "brain", key: "agent") {
            VStack(alignment: .leading, spacing: Df.space2) {
                HStack(spacing: Df.space2) {
                    // Fresh session
                    if hasSource {
                        actionBtn("plus.circle", "Fresh", .primary) {
                            DeskfloorApp.openInITerm("cd \(project.localPath!) && claude")
                        }
                    } else if hasRepo {
                        actionBtn("plus.circle", "Fresh", .primary) {
                            DeskfloorApp.openInITerm("cd ~/Nissan && gh repo clone \(project.repo!) 2>/dev/null; cd ~/Nissan/\(project.name) && claude")
                        }
                    } else {
                        disabledAction("plus.circle", "Fresh", hint: "needs source")
                    }

                    // Resume — only if there are recent threads
                    if let latest = agentThreads.first, latest.status == .live || latest.status == .paused {
                        actionBtn("arrow.counterclockwise", "Resume", .accent) {
                            if let path = project.localPath {
                                DeskfloorApp.openInITerm("cd \(path) && claude --continue")
                            }
                        }
                    } else {
                        disabledAction("arrow.counterclockwise", "Resume", hint: agentThreads.isEmpty ? "no sessions" : "none active")
                    }

                    // History
                    let count = agentThreads.count
                    if count > 0 {
                        actionBtn("clock.arrow.circlepath", "History (\(count))", .secondary) {
                            // Could navigate to skein view filtered to this project
                        }
                    } else {
                        disabledAction("clock.arrow.circlepath", "History", hint: "none yet")
                    }

                    Spacer()
                }

                // Show latest thread inline if any
                if let latest = agentThreads.first {
                    HStack(spacing: Df.space2) {
                        Circle()
                            .fill(latest.status.color)
                            .frame(width: 6, height: 6)
                        Text(latest.title)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textSecondary(scheme))
                            .lineLimit(1)
                        Spacer()
                        Text(latest.updatedAt, style: .relative)
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }
                    .padding(.horizontal, Df.space2)
                }
            }
        }
    }

    // MARK: - Deploy & Ops Section

    private var deploySection: some View {
        actionSection("DEPLOY & OPS", icon: "server.rack", key: "deploy") {
            VStack(alignment: .leading, spacing: Df.space2) {
                HStack(spacing: Df.space2) {
                    // Deploy
                    if hasDeploy, let cmd = project.deployCommand {
                        actionBtn("paperplane.fill", "Deploy", .accent) {
                            let host = project.deployHost!
                            let remote = project.deployPath.map { "cd \($0) && " } ?? ""
                            DeskfloorApp.openInITerm("ssh \(host) '\(remote)\(cmd)'")
                        }
                    } else {
                        disabledAction("paperplane.fill", "Deploy", hint: hasDeploy ? "set command" : "configure below")
                    }

                    // Live view
                    if let url = project.deployURL {
                        actionBtn("globe", "Live", .primary) {
                            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        }
                    } else {
                        disabledAction("globe", "Live", hint: "set URL")
                    }

                    // Server state
                    if let hostInfo = deployHostInfo {
                        actionBtn("cpu", "Server", .secondary) {
                            DeskfloorApp.sshJump(host: hostInfo.name)
                        }
                    } else if hasDeploy {
                        actionBtn("cpu", "Server", .secondary) {
                            DeskfloorApp.sshJump(host: project.deployHost!)
                        }
                    } else {
                        disabledAction("cpu", "Server", hint: "set host")
                    }

                    // Logs
                    if hasDeploy {
                        actionBtn("doc.text.magnifyingglass", "Logs", .secondary) {
                            let host = project.deployHost!
                            let path = project.deployPath ?? "~"
                            DeskfloorApp.openInITerm("ssh \(host) 'cd \(path) && tail -100f *.log 2>/dev/null || journalctl -n 100 -f'")
                        }
                    } else {
                        disabledAction("doc.text.magnifyingglass", "Logs", hint: "set host")
                    }

                    Spacer()
                }

                // Inline status row — fleet host + CI
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

                // Configure deploy — expandable inline
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

    // MARK: - Git Card

    @ViewBuilder
    private var gitCard: some View {
        if project.gitBranch != nil || project.localPath != nil {
            DfCard {
                VStack(alignment: .leading, spacing: Df.space2) {
                    HStack(spacing: Df.space4) {
                        if let branch = project.gitBranch {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Df.textTertiary(scheme))
                                Text(branch)
                                    .font(Df.monoSmallFont)
                                    .foregroundStyle(Df.textPrimary(scheme))
                            }
                        }
                        if project.commitCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "number")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Df.textTertiary(scheme))
                                Text("\(project.commitCount)")
                                    .font(Df.monoSmallFont)
                                    .foregroundStyle(Df.textSecondary(scheme))
                            }
                        }
                        if let dirty = project.dirtyFiles {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(dirty > 0 ? Df.uncertain : Df.certain)
                                    .frame(width: 6, height: 6)
                                Text(dirty > 0 ? "\(dirty) dirty" : "clean")
                                    .font(Df.monoSmallFont)
                                    .foregroundStyle(dirty > 0 ? Df.uncertain : Df.certain)
                            }
                        }
                        Spacer()
                        if let lastActivity = project.lastActivity {
                            Text(lastActivity, style: .relative)
                                .font(Df.monoSmallFont)
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                    }

                    if let msg = project.lastCommitMessage, !msg.isEmpty {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Df.textQuaternary(scheme))
                                .frame(width: 2, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                            Text(msg)
                                .font(Df.monoSmallFont)
                                .foregroundStyle(Df.textTertiary(scheme))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(Df.space3)
            }
        }
    }

    // MARK: - Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: Df.space2) {
            DfSectionHeader(title: "Progress", count: project.progressNotes.isEmpty ? nil : project.progressNotes.count)

            ForEach(project.progressNotes.suffix(5).reversed()) { note in
                HStack(alignment: .top, spacing: Df.space2) {
                    Text(shortDate(note.date))
                        .font(Df.monoSmallFont)
                        .foregroundStyle(Df.textQuaternary(scheme))
                        .frame(width: 50, alignment: .leading)
                    Text(note.note)
                        .font(Df.captionFont)
                        .foregroundStyle(Df.textSecondary(scheme))
                    Spacer()
                    Button(action: { project.progressNotes.removeAll { $0.id == note.id } }) {
                        Image(systemName: "xmark").font(.system(size: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Df.textQuaternary(scheme))
                    .opacity(0.5)
                }
            }

            HStack(spacing: Df.space2) {
                DfInsetField {
                    TextField("Note...", text: $newNoteText)
                        .font(Df.captionFont)
                        .textFieldStyle(.plain)
                        .onSubmit { addNote() }
                }
                Button(action: addNote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(newNoteText.isEmpty ? Df.textQuaternary(scheme) : Df.certain)
                }
                .buttonStyle(.plain)
                .disabled(newNoteText.isEmpty)
            }
        }
    }

    // MARK: - Tags & Connections

    private var tagsAndConnections: some View {
        HStack(alignment: .top, spacing: Df.space5) {
            VStack(alignment: .leading, spacing: Df.space1) {
                Text("TAGS").font(Df.microFont).foregroundStyle(Df.textTertiary(scheme))
                FlowLayout(spacing: 4) {
                    ForEach(project.tags, id: \.self) { tag in
                        DfPill(text: tag, color: Df.info)
                            .onTapGesture { project.tags.removeAll { $0 == tag } }
                    }
                }
                TextField("add...", text: $newTag)
                    .font(Df.monoSmallFont).textFieldStyle(.plain)
                    .foregroundStyle(Df.textTertiary(scheme)).frame(width: 80)
                    .onSubmit {
                        guard !newTag.isEmpty else { return }
                        project.tags.append(newTag); newTag = ""
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Df.space1) {
                Text("CONNECTIONS").font(Df.microFont).foregroundStyle(Df.textTertiary(scheme))
                FlowLayout(spacing: 4) {
                    ForEach(project.connections, id: \.self) { conn in
                        DfPill(text: conn, color: Df.agent)
                            .onTapGesture { project.connections.removeAll { $0 == conn } }
                    }
                }
                TextField("link...", text: $newConnection)
                    .font(Df.monoSmallFont).textFieldStyle(.plain)
                    .foregroundStyle(Df.textTertiary(scheme)).frame(width: 80)
                    .onSubmit {
                        guard !newConnection.isEmpty else { return }
                        project.connections.append(newConnection); newConnection = ""
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Encumbrances

    private var encumbranceList: some View {
        VStack(alignment: .leading, spacing: Df.space1) {
            Text("ENCUMBRANCES").font(Df.microFont).foregroundStyle(Df.textTertiary(scheme))
            ForEach(project.encumbrances) { enc in
                HStack(spacing: Df.space2) {
                    Circle().fill(enc.kind.dotColor).frame(width: 6, height: 6)
                    Text(enc.kind.label).font(Df.monoSmallFont).foregroundStyle(Df.textSecondary(scheme))
                    Text(enc.description).font(Df.monoSmallFont).foregroundStyle(Df.textTertiary(scheme))
                    Spacer()
                    Button(action: { project.encumbrances.removeAll { $0.id == enc.id } }) {
                        Image(systemName: "xmark").font(.system(size: 7))
                    }
                    .buttonStyle(.plain).foregroundStyle(Df.textQuaternary(scheme))
                }
            }
        }
    }

    // MARK: - Why

    private var whyBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WHY").font(Df.microFont).foregroundStyle(Df.textTertiary(scheme))
            if isNew || project.why.isEmpty {
                TextField("Why does this project exist?", text: $project.why)
                    .font(Df.captionFont).textFieldStyle(.plain)
            } else {
                Text(project.why)
                    .font(Df.captionFont).foregroundStyle(Df.textSecondary(scheme))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Df.space3) {
            if !isNew {
                Button(action: { confirmDelete = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Df.critical.opacity(0.6))
                }
                .buttonStyle(.plain).help("Delete project")
            }

            Spacer()

            Button("Cancel") { onCancel() }
                .buttonStyle(.plain)
                .font(Df.bodyFont)
                .foregroundStyle(Df.textTertiary(scheme))
                .keyboardShortcut(.escape)

            Button(action: { onSave(project) }) {
                Text(isNew ? "Create" : "Save")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Df.space4)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Df.accent)
                            .shadow(color: Df.accent.opacity(0.3), radius: 4, y: 2)
                    )
            }
            .buttonStyle(.plain).keyboardShortcut(.return)
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space3)
        .background(Df.surface(scheme).opacity(0.6))
    }

    // MARK: - Reusable Components

    /// A collapsible action section with header.
    private func actionSection<Content: View>(
        _ title: String,
        icon: String,
        key: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Df.space2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expandedSections.contains(key) {
                        expandedSections.remove(key)
                    } else {
                        expandedSections.insert(key)
                    }
                }
            } label: {
                HStack(spacing: Df.space2) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Df.textTertiary(scheme))
                        .frame(width: 14)
                    Text(title)
                        .font(Df.microFont)
                        .foregroundStyle(Df.textTertiary(scheme))

                    // Capability indicator — how many actions are available
                    capabilityDots(for: key)

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Df.textQuaternary(scheme))
                        .rotationEffect(.degrees(expandedSections.contains(key) ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if expandedSections.contains(key) {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Colored dots showing how many capabilities are available in a section.
    private func capabilityDots(for key: String) -> some View {
        let (available, total) = capabilityCounts(for: key)
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < available ? Df.certain : Df.textQuaternary(scheme))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func capabilityCounts(for key: String) -> (available: Int, total: Int) {
        switch key {
        case "source":
            var a = 0
            if hasSource { a += 1 }
            if hasRepo { a += 1 }
            return (a, 2)
        case "agent":
            var a = 0
            if hasSource || hasRepo { a += 1 } // fresh
            if !agentThreads.isEmpty { a += 1 } // history
            if agentThreads.first?.status == .live || agentThreads.first?.status == .paused { a += 1 } // resume
            return (a, 3)
        case "deploy":
            var a = 0
            if hasDeploy && project.deployCommand != nil { a += 1 }
            if hasLiveURL { a += 1 }
            if hasDeploy { a += 2 } // server + logs
            return (a, 4)
        default:
            return (0, 0)
        }
    }

    /// An enabled action button.
    private func actionBtn(_ icon: String, _ label: String, _ style: ActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(style.color(scheme))
            .padding(.horizontal, Df.space2)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(style.bg(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(style.border(scheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// A disabled action with hint text showing what's needed.
    private func disabledAction(_ icon: String, _ label: String, hint: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Df.textQuaternary(scheme))
            .padding(.horizontal, Df.space2)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Df.inset(scheme).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Df.border(scheme).opacity(0.3), lineWidth: 0.5)
                    )
            )

            Text(hint)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Df.textQuaternary(scheme))
        }
    }

    enum ActionStyle {
        case primary, secondary, accent

        func color(_ scheme: ColorScheme) -> Color {
            switch self {
            case .primary: return Df.textPrimary(scheme)
            case .secondary: return Df.textSecondary(scheme)
            case .accent: return Df.accent
            }
        }

        func bg(_ scheme: ColorScheme) -> Color {
            switch self {
            case .primary: return Df.elevated(scheme)
            case .secondary: return Df.surface(scheme)
            case .accent: return Df.accent.opacity(scheme == .dark ? 0.12 : 0.08)
            }
        }

        func border(_ scheme: ColorScheme) -> Color {
            switch self {
            case .accent: return Df.accent.opacity(0.3)
            default: return Df.border(scheme)
            }
        }
    }

    private func chipMenu<Content: View>(_ label: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(Df.monoSmallFont)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Df.textSecondary(scheme))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(scheme == .dark ? 0.15 : 0.1))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Helpers

    private func addNote() {
        guard !newNoteText.isEmpty else { return }
        project.progressNotes.append(ProgressNote(date: Date(), note: newNoteText))
        newNoteText = ""
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
