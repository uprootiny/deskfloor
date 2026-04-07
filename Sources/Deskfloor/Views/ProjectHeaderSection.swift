import SwiftUI

struct ProjectHeroBar: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var project: Project
    var isNew: Bool
    @Binding var editingDescription: Bool

    var body: some View {
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
}
