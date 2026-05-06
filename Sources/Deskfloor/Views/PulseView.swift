import SwiftUI
import AppKit

/// First Pulse tile — a single CPU number with its full Probe instrumentation
/// surfaced. Treats the runner as the single source of truth; mirrors every
/// invariant from the Probe spec into something visible.
///
/// When the parent window's occlusion state excludes `.visible`, the runner
/// pauses. When it returns to visible, the runner resumes. This keeps the
/// app from sampling Mach in the background.
struct PulseView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var runner = ProbeRunner(probe: CPUProbe())

    var body: some View {
        VStack(spacing: Df.space5) {
            Spacer()
            cpuTile
            Spacer()
            instrumentationStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Df.canvas(scheme))
        .onAppear { runner.start() }
        .onDisappear { runner.pause() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.isMainWindow || window.isKeyWindow
            else { return }
            if window.occlusionState.contains(.visible) {
                runner.start()
            } else {
                runner.pause()
            }
        }
    }

    // MARK: - The tile

    private var cpuTile: some View {
        VStack(spacing: Df.space3) {
            Text("CPU")
                .font(Df.microFont)
                .foregroundStyle(Df.textTertiary(scheme))
                .tracking(2)

            Text(displayValue)
                .font(.system(size: 96, weight: .ultraLight, design: .default))
                .foregroundStyle(displayColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: displayValue)

            Text(displayCaption)
                .font(Df.captionFont)
                .foregroundStyle(Df.textTertiary(scheme))
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space4)
        .background(
            RoundedRectangle(cornerRadius: Df.radiusLarge)
                .fill(Df.surface(scheme))
                .shadow(color: Df.bevelShadow(scheme).opacity(0.4), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Df.radiusLarge)
                .strokeBorder(Df.bevelHighlight(scheme).opacity(0.3), lineWidth: 0.5)
        )
        .frame(minWidth: 320)
    }

    // MARK: - Instrumentation strip — diagnostics in plain sight

    private var instrumentationStrip: some View {
        HStack(spacing: Df.space4) {
            metric("name",  runner.probe.name)
            metric("ticks", "\(runner.reading.ticksSucceeded)/\(runner.reading.ticksTotal)")
            metric("p50",   formatLatency(runner.reading.latencyP50))
            metric("p95",   formatLatency(runner.reading.latencyP95))
            metric("circuit", circuitLabel)
            if let s = runner.reading.staleness() {
                metric("age", String(format: "%.1fs", s))
            } else {
                metric("age", "—")
            }
            if runner.reading.paused {
                metric("state", "paused")
            }
            Spacer()
            Button {
                runner.nudge()
            } label: {
                Label("Force tick", systemImage: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Df.textSecondary(scheme))
        }
        .padding(.horizontal, Df.space4)
        .padding(.vertical, Df.space2)
        .background(Df.surface(scheme).opacity(0.5))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Df.bevelHighlight(scheme).opacity(0.2)),
            alignment: .top
        )
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Df.textQuaternary(scheme))
                .tracking(1)
            Text(value)
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textSecondary(scheme))
        }
    }

    // MARK: - Derived display state

    /// `runner.reading.value` is `Double??` — outer-nil means we've never had a
    /// successful tick; outer-some-inner-nil means we ticked but had no delta
    /// yet (CPUProbe's first sample). Both display as em-dash.
    private var unwrappedValue: Double? {
        guard case let .some(inner) = runner.reading.value else { return nil }
        return inner
    }

    private var displayValue: String {
        guard let v = unwrappedValue else { return "—" }
        return String(format: "%.0f%%", v * 100)
    }

    private var displayColor: Color {
        if runner.reading.lastError != nil { return Df.critical }
        if runner.reading.isStale(cadence: runner.probe.preferredCadence) {
            return Df.uncertain
        }
        guard let v = unwrappedValue else {
            return Df.textTertiary(scheme)
        }
        if v >= 0.85 { return Df.critical }
        if v >= 0.65 { return Df.uncertain }
        return Df.textPrimary(scheme)
    }

    private var displayCaption: String {
        if let err = runner.reading.lastError {
            return err.userFacing
        }
        if let s = runner.reading.staleness(),
           s > runner.probe.preferredCadence.seconds * 3 {
            return String(format: "stale %.0fs", s)
        }
        if unwrappedValue == nil {
            return "warming up…"
        }
        switch runner.reading.circuit {
        case .closed: return "live"
        case .halfOpen(let n): return "recovering · \(n) probes left"
        case .open(let until):
            let dt = max(0, until.timeIntervalSinceNow)
            return String(format: "circuit open · retry in %.0fs", dt)
        }
    }

    private var circuitLabel: String {
        switch runner.reading.circuit {
        case .closed: return "closed"
        case .halfOpen(let n): return "half · \(n)"
        case .open: return "open"
        }
    }

    private func formatLatency(_ d: Duration) -> String {
        let secs = d.seconds
        if secs < 0.001 { return "<1ms" }
        if secs < 1 { return String(format: "%.1fms", secs * 1000) }
        return String(format: "%.2fs", secs)
    }
}
