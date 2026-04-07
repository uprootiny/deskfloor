import SwiftUI

struct ProjectGitCard: View {
    @Environment(\.colorScheme) private var scheme
    var project: Project

    var body: some View {
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
}

struct ProjectProgressBlock: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    @Binding var newNoteText: String

    var body: some View {
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

struct ProjectTagsAndConnections: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    @Binding var newTag: String
    @Binding var newConnection: String

    var body: some View {
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
}

struct ProjectEncumbranceList: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project

    var body: some View {
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
}

struct ProjectWhyBlock: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var isNew: Bool

    var body: some View {
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
}
