import SwiftUI

struct ViewModeToolbar: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var viewMode: ViewMode
    @Binding var sortOrder: SortOrder
    var isScanning: Bool
    var scanProgress: (done: Int, total: Int)
    var importInProgress: Bool
    var onScan: () -> Void
    var onRefresh: () -> Void
    var onImport: () -> Void
    var onNewProject: () -> Void

    var body: some View {
        HStack(spacing: Df.space3) {
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    Button(action: { viewMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                viewMode == mode
                                    ? Df.textPrimary(scheme)
                                    : Df.textTertiary(scheme)
                            )
                            .frame(width: 28, height: 24)
                            .background(
                                viewMode == mode
                                    ? Df.elevated(scheme)
                                    : .clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
                            .shadow(
                                color: viewMode == mode ? Df.bevelShadow(scheme) : .clear,
                                radius: 2, y: 1
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(2)
            .background(Df.inset(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall + 2))

            Text(viewMode.label)
                .font(Df.captionFont)
                .foregroundStyle(Df.textSecondary(scheme))

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Spacer()

            if importInProgress {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            }

            if isScanning {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    if scanProgress.total > 0 {
                        Text("\(scanProgress.done)/\(scanProgress.total)")
                            .font(Df.monoSmallFont)
                            .foregroundStyle(Df.textTertiary(scheme))
                    }
                }
            }

            toolbarButton("Scan", icon: "folder.badge.gearshape", disabled: isScanning, action: onScan)
            toolbarButton("Refresh", icon: "arrow.clockwise", action: onRefresh)
            toolbarButton("Import", icon: "square.and.arrow.down", disabled: importInProgress, action: onImport)

            Button(action: onNewProject) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("New")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Df.accent)
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space2)
        .background(Df.surface(scheme))
    }

    private func toolbarButton(_ label: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Df.textSecondary(scheme))
        .disabled(disabled)
        .help(label)
    }
}
