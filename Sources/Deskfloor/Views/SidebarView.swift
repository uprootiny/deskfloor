import SwiftUI

struct SidebarView: View {
    @Binding var searchText: String
    @Binding var selectedPerspectives: Set<Perspective>
    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedEncumbranceKinds: Set<EncumbranceKind>
    @Binding var handoffOnly: Bool
    @Binding var encumberedOnly: Bool
    let projectCount: Int
    let filteredCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Count
            Text("\(filteredCount) of \(projectCount) projects")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))

            Divider().background(Color.white.opacity(0.1))

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

            Divider().background(Color.white.opacity(0.1))

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

            Divider().background(Color.white.opacity(0.1))

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

            Divider().background(Color.white.opacity(0.1))

            // Quick filters
            filterSection("Quick Filters") {
                Toggle(isOn: $handoffOnly) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                        Text("Handoff ready")
                            .font(.system(size: 11))
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $encumberedOnly) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                        Text("Has encumbrances")
                            .font(.system(size: 11))
                    }
                }
                .toggleStyle(.checkbox)
            }

            Spacer()

            // Clear all filters
            if hasActiveFilters {
                Button(action: clearAll) {
                    Text("Clear all filters")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .padding(12)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
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
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? .white : .white.opacity(0.4))
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
