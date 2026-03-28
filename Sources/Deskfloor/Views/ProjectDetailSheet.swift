import SwiftUI

struct ProjectDetailSheet: View {
    @Binding var project: Project
    var isNew: Bool = false
    var onSave: (Project) -> Void
    var onDelete: (() -> Void)?
    var onCancel: () -> Void

    @State private var newTag = ""
    @State private var newConnection = ""
    @State private var newNoteText = ""
    @State private var newEncKind: EncumbranceKind = .dependency
    @State private var newEncDesc = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Project" : "Edit Project")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                Button("Save") { onSave(project) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.3, green: 0.7, blue: 0.5))
            }
            .padding()

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        field("Name") {
                            TextField("Project name", text: $project.name)
                                .textFieldStyle(.plain)
                        }
                        field("Repo") {
                            TextField("owner/repo", text: Binding(
                                get: { project.repo ?? "" },
                                set: { project.repo = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.plain)
                        }
                        field("Description") {
                            TextField("What is this?", text: $project.description)
                                .textFieldStyle(.plain)
                        }
                        field("Why") {
                            TextField("Why does this exist?", text: $project.why)
                                .textFieldStyle(.plain)
                        }
                    }

                    HStack(spacing: 16) {
                        field("Status") {
                            Picker("", selection: $project.status) {
                                ForEach(Status.allCases) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                        }
                        field("Perspective") {
                            Picker("", selection: $project.perspective) {
                                ForEach(Perspective.allCases) { p in
                                    Text(p.label).tag(p)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Tags
                    field("Tags") {
                        FlowLayout(spacing: 4) {
                            ForEach(project.tags, id: \.self) { tag in
                                tagChip(tag) {
                                    project.tags.removeAll { $0 == tag }
                                }
                            }
                        }
                        HStack {
                            TextField("Add tag", text: $newTag)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    if !newTag.isEmpty {
                                        project.tags.append(newTag)
                                        newTag = ""
                                    }
                                }
                            Button("+") {
                                if !newTag.isEmpty {
                                    project.tags.append(newTag)
                                    newTag = ""
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Connections
                    field("Connections") {
                        FlowLayout(spacing: 4) {
                            ForEach(project.connections, id: \.self) { conn in
                                tagChip(conn) {
                                    project.connections.removeAll { $0 == conn }
                                }
                            }
                        }
                        HStack {
                            TextField("Related project name", text: $newConnection)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    if !newConnection.isEmpty {
                                        project.connections.append(newConnection)
                                        newConnection = ""
                                    }
                                }
                            Button("+") {
                                if !newConnection.isEmpty {
                                    project.connections.append(newConnection)
                                    newConnection = ""
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Encumbrances
                    field("Encumbrances") {
                        ForEach(project.encumbrances) { enc in
                            HStack {
                                Circle().fill(enc.kind.dotColor).frame(width: 8, height: 8)
                                Text(enc.kind.label).font(.system(size: 11, weight: .medium))
                                Text(enc.description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Button(action: {
                                    project.encumbrances.removeAll { $0.id == enc.id }
                                }) {
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        HStack {
                            Picker("", selection: $newEncKind) {
                                ForEach(EncumbranceKind.allCases) { k in
                                    Text(k.label).tag(k)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            TextField("Description", text: $newEncDesc)
                                .textFieldStyle(.plain)
                                .onSubmit { addEncumbrance() }
                            Button("+") { addEncumbrance() }
                                .buttonStyle(.plain)
                        }
                    }

                    // Handoff
                    HStack {
                        Toggle("Handoff ready", isOn: $project.handoffReady)
                            .toggleStyle(.checkbox)
                    }
                    if project.handoffReady {
                        field("Handoff Notes") {
                            TextEditor(text: $project.handoffNotes)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(minHeight: 60)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // Progress notes
                    field("Progress Notes") {
                        ForEach(project.progressNotes) { note in
                            HStack(alignment: .top) {
                                Text(note.date, style: .date)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(width: 80, alignment: .leading)
                                Text(note.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                Button(action: {
                                    project.progressNotes.removeAll { $0.id == note.id }
                                }) {
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        HStack {
                            TextField("Add a note...", text: $newNoteText)
                                .textFieldStyle(.plain)
                                .onSubmit { addNote() }
                            Button("+") { addNote() }
                                .buttonStyle(.plain)
                        }
                    }

                    if !isNew, let onDelete = onDelete {
                        Divider().background(Color.white.opacity(0.1))
                        Button("Delete Project") {
                            onDelete()
                        }
                        .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.3))
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 560, height: 650)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
            content()
        }
    }

    private func tagChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 10, design: .monospaced))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.08))
        .foregroundStyle(.white.opacity(0.7))
        .clipShape(Capsule())
    }

    private func addEncumbrance() {
        guard !newEncDesc.isEmpty else { return }
        project.encumbrances.append(Encumbrance(kind: newEncKind, description: newEncDesc))
        newEncDesc = ""
    }

    private func addNote() {
        guard !newNoteText.isEmpty else { return }
        project.progressNotes.append(ProgressNote(date: Date(), note: newNoteText))
        newNoteText = ""
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
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
