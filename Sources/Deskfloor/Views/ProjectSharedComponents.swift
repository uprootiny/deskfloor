import SwiftUI

enum ProjectActionStyle {
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

struct ProjectActionBtn: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let label: String
    let style: ProjectActionStyle
    let action: () -> Void

    init(_ icon: String, _ label: String, _ style: ProjectActionStyle, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.style = style; self.action = action
    }

    var body: some View {
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
}

struct ProjectDisabledAction: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let label: String
    let hint: String

    init(_ icon: String, _ label: String, hint: String) {
        self.icon = icon; self.label = label; self.hint = hint
    }

    var body: some View {
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
}

struct ProjectActionSection<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String
    let key: String
    @Binding var expandedSections: Set<String>
    @Binding var project: Project
    @ViewBuilder let content: () -> Content

    private var hasSource: Bool { project.localPath != nil }
    private var hasRepo: Bool { project.repo != nil }
    private var hasDeploy: Bool { project.deployHost != nil }
    private var hasLiveURL: Bool { project.deployURL != nil }

    var body: some View {
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
                    capabilityDots
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

    private var capabilityDots: some View {
        let (available, total) = capabilityCounts
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < available ? Df.certain : Df.textQuaternary(scheme))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var capabilityCounts: (available: Int, total: Int) {
        switch key {
        case "source":
            var a = 0
            if hasSource { a += 1 }
            if hasRepo { a += 1 }
            return (a, 2)
        case "agent":
            var a = 0
            if hasSource || hasRepo { a += 1 }
            return (a, 3)
        case "deploy":
            var a = 0
            if hasDeploy && project.deployCommand != nil { a += 1 }
            if hasLiveURL { a += 1 }
            if hasDeploy { a += 2 }
            return (a, 4)
        default:
            return (0, 0)
        }
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
