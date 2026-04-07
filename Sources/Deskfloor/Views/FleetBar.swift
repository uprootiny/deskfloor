import SwiftUI

struct FleetBar: View {
    @Environment(\.colorScheme) private var scheme
    var fleet: FleetStore

    var body: some View {
        HStack(spacing: Df.space4) {
            if fleet.isReachable {
                ForEach(fleet.hosts) { host in
                    Button(action: { DeskfloorApp.sshJump(host: host.name) }) {
                        HStack(spacing: 4) {
                            Text(host.sigil)
                                .font(.system(size: 10))
                            Text(host.name)
                                .font(Df.monoSmallFont)
                                .foregroundStyle(Df.textSecondary(scheme))
                            DfPill(
                                text: String(format: "%.0f", host.load),
                                color: host.load > 4 ? Df.critical : host.load > 2 ? Df.uncertain : Df.certain
                            )
                            DfPill(
                                text: "\(host.diskPercent)%",
                                color: host.diskPercent >= 85 ? Df.uncertain : Df.certain
                            )
                            if host.claudeCount > 0 {
                                DfPill(text: "\(host.claudeCount)cl", color: Df.agent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("SSH to \(host.name)")
                }
            } else {
                Text("Fleet offline")
                    .font(Df.captionFont)
                    .foregroundStyle(Df.textTertiary(scheme))
            }

            Spacer()

            if let update = fleet.lastUpdate {
                Text(update, style: .relative)
                    .font(Df.monoSmallFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }

            Text("Ctrl+Space: Launcher")
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textQuaternary(scheme))
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, 5)
        .background(Df.surface(scheme).opacity(0.8))
    }
}
