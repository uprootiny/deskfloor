import SwiftUI

struct ProjectSurfaceBadge: View {
    @Environment(\.colorScheme) private var scheme
    let surfaceStore: SurfaceStore
    let projectID: UUID

    private var counts: [SurfaceKind: Int] {
        surfaceStore.surfaceCounts(for: projectID)
    }

    var body: some View {
        let activeCounts = SurfaceKind.allCases.compactMap { kind -> (SurfaceKind, Int)? in
            guard let count = counts[kind], count > 0 else { return nil }
            return (kind, count)
        }

        if !activeCounts.isEmpty {
            HStack(spacing: 4) {
                ForEach(activeCounts, id: \.0.rawValue) { kind, count in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(kind.color)
                            .frame(width: 6, height: 6)
                        if count > 1 {
                            Text("\(count)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Df.textTertiary(scheme))
                        }
                    }
                    .help("\(count) \(kind.label)")
                }
            }
        }
    }
}
