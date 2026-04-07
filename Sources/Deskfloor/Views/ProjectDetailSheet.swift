import SwiftUI

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
    @State private var editingDescription = false
    @State private var confirmDelete = false
    @State private var showDeployConfig = false
    @State private var expandedSections: Set<String> = ["source", "agent"]

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeroBar(project: $project, isNew: isNew, editingDescription: $editingDescription)
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Df.space4) {
                    ProjectSourceSection(project: $project, expandedSections: $expandedSections)
                    ProjectAgentSection(project: $project, expandedSections: $expandedSections, skein: skein)
                    ProjectDeploySection(project: $project, expandedSections: $expandedSections, fleet: fleet, dataBus: dataBus, showDeployConfig: $showDeployConfig)
                    ProjectGitCard(project: project)
                    ProjectProgressBlock(project: $project, newNoteText: $newNoteText)
                    if !project.tags.isEmpty || !project.connections.isEmpty || isNew {
                        ProjectTagsAndConnections(project: $project, newTag: $newTag, newConnection: $newConnection)
                    }
                    if !project.encumbrances.isEmpty {
                        ProjectEncumbranceList(project: $project)
                    }
                    if !project.why.isEmpty || isNew {
                        ProjectWhyBlock(project: $project, isNew: isNew)
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
}
