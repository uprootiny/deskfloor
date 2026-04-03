import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var searchText: String
    @Binding var selectedPerspectives: Set<Perspective>
    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedEncumbranceKinds: Set<EncumbranceKind>
    @Binding var handoffOnly: Bool
    @Binding var encumberedOnly: Bool
    let projectCount: Int
    let filteredCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Df.space4) {
            // Search — inset field
            DfInsetField {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Df.textTertiary(scheme))
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Df.bodyFont)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Count
            Text("\(filteredCount) of \(projectCount) projects")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textTertiary(scheme))

            Divider().opacity(0.5)

            // Perspectives
            filterSection("Perspective") {
                ForEach(Perspective.allCases) { p in
                    filterToggle(
                        label: p.label,
                        color: p.color,
                        isOn: selectedPerspectives.contains(p),
                        toggle: { toggleSet(&selectedPerspectives, p) }
                    )
                }
            }

            Divider().opacity(0.5)

            // Statuses
            filterSection("Status") {
                ForEach(Status.allCases) { s in
                    filterToggle(
                        label: s.label,
                        color: s.color,
                        isOn: selectedStatuses.contains(s),
                        toggle: { toggleSet(&selectedStatuses, s) }
                    )
                }
            }

            Divider().opacity(0.5)

            // Encumbrances
            filterSection("Encumbrances") {
                ForEach(EncumbranceKind.allCases) { k in
                    filterToggle(
                        label: k.label,
                        color: k.dotColor,
                        isOn: selectedEncumbranceKinds.contains(k),
                        toggle: { toggleSet(&selectedEncumbranceKinds, k) }
                    )
                }
            }

            Divider().opacity(0.5)

            // Quick filters
            filterSection("Quick Filters") {
                Toggle(isOn: $handoffOnly) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                        Text("Handoff ready")
                            .font(Df.captionFont)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $encumberedOnly) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                        Text("Has encumbrances")
                            .font(Df.captionFont)
                    }
                }
                .toggleStyle(.checkbox)
            }

            Spacer()

            // Clear all filters
            if hasActiveFilters {
                Button(action: clearAll) {
                    Text("Clear all filters")
                        .font(Df.captionFont)
                        .foregroundStyle(Df.textSecondary(scheme))
                }
                .buttonStyle(.plain)
                .padding(.bottom, Df.space2)
            }
        }
        .padding(Df.space3)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedPerspectives.isEmpty || !selectedStatuses.isEmpty
        || !selectedEncumbranceKinds.isEmpty || handoffOnly || encumberedOnly
    }

    private func clearAll() {
        searchText = ""
        selectedPerspectives = []
        selectedStatuses = []
        selectedEncumbranceKinds = []
        handoffOnly = false
        encumberedOnly = false
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Df.space1) {
            Text(title)
                .font(Df.microFont)
                .foregroundStyle(Df.textTertiary(scheme))
                .textCase(.uppercase)
            content()
        }
    }

    private func filterToggle(label: String, color: Color, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? color : color.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .shadow(color: isOn ? color.opacity(0.4) : .clear, radius: 3)
                Text(label)
                    .font(Df.captionFont)
                    .foregroundStyle(isOn ? Df.textPrimary(scheme) : Df.textTertiary(scheme))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSet<T: Hashable>(_ set: inout Set<T>, _ item: T) {
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
    }
}
