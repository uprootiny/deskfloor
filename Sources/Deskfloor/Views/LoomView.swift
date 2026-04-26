import SwiftUI

/// Minimal placeholder while the design slice is being engineered in window 29830.
/// Renders a recap of the current LoomStore state so the view-mode is wired and
/// the Cmd+8 routing is exercised. Replace with the real grid + weft bar + shelf.
struct LoomView: View {
    @Environment(\.colorScheme) private var scheme
    let skein: SkeinStore
    let loom: LoomStore

    var body: some View {
        VStack(spacing: Df.space4) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Df.textQuaternary(scheme))
            Text("Loom")
                .font(Df.titleFont)
                .foregroundStyle(Df.textSecondary(scheme))
            Text("Multi-warp comparison view — design slice in flight (Ghostty window 29830)")
                .font(Df.captionFont)
                .foregroundStyle(Df.textTertiary(scheme))

            VStack(alignment: .leading, spacing: Df.space2) {
                summaryRow(label: "Schema version", value: "\(loom.schemaVersion)")
                summaryRow(label: "Visible warps",  value: "\(loom.visibleWarps.count) / 7")
                summaryRow(label: "Fired wefts",    value: "\(loom.wefts.count)")
                summaryRow(label: "Shelf items",    value: "\(loom.shelfExcerptIDs.count)")
                summaryRow(label: "Skein threads",  value: "\(skein.threads.count)")
            }
            .padding(Df.space4)
            .background(Df.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Df.radiusSmall)
                    .strokeBorder(Df.bevelHighlight(scheme).opacity(0.3), lineWidth: 0.5)
            )

            Button("Seed warps from recent threads") {
                loom.seedOnce(from: skein, count: 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Df.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Df.canvas(scheme))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Df.captionFont)
                .foregroundStyle(Df.textTertiary(scheme))
            Spacer()
            Text(value)
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textPrimary(scheme))
        }
        .frame(width: 320)
    }
}
