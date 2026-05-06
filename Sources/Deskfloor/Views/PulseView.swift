import SwiftUI
import AppKit

/// Pulse — situational awareness surface. Two tiles for now (CPU, memory),
/// each backed by an independent `ProbeRunner`. Every probe shares the same
/// instrumentation contract (cadence, p50/p95, circuit, occlusion-pause), so
/// adding a third probe is a copy-paste of one runner declaration plus one
/// `tile(...)` call.
///
/// When the parent window's occlusion state excludes `.visible`, every
/// runner pauses. When it returns to visible, every runner resumes. Saves
/// cycles you can't see.
struct PulseView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var cpu = ProbeRunner(probe: CPUProbe())
    @State private var memory = ProbeRunner(probe: MemoryProbe())

    var body: some View {
        VStack(spacing: Df.space5) {
            Spacer()
            HStack(spacing: Df.space5) {
                tile(
                    title: "CPU",
                    valueText: cpuValueText,
                    captionText: caption(for: cpu.reading,
                                         cadence: cpu.probe.preferredCadence,
                                         valueIsAbsent: cpuUnwrapped == nil),
                    color: color(percent: cpuUnwrapped,
                                 reading: cpu.reading,
                                 cadence: cpu.probe.preferredCadence)
                )
                tile(
                    title: "MEM",
                    valueText: memoryValueText,
                    captionText: caption(for: memory.reading,
                                         cadence: memory.probe.preferredCadence,
                                         valueIsAbsent: memoryUnwrapped == nil),
                    color: color(percent: memoryUnwrapped,
                                 reading: memory.reading,
                                 cadence: memory.probe.preferredCadence)
                )
            }
            Spacer()
            instrumentationStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Df.canvas(scheme))
        .onAppear {
            cpu.start()
            memory.start()
        }
        .onDisappear {
            cpu.pause()
            memory.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.isMainWindow || window.isKeyWindow else { return }
            let visible = window.occlusionState.contains(.visible)
            if visible {
                cpu.start(); memory.start()
            } else {
                cpu.pause(); memory.pause()
            }
        }
    }

    // MARK: - Tile

    private func tile(title: String, valueText: String, captionText: String, color: Color) -> some View {
        VStack(spacing: Df.space3) {
            Text(title)
                .font(Df.microFont)
                .foregroundStyle(Df.textTertiary(scheme))
                .tracking(2)
            Text(valueText)
                .font(.system(size: 96, weight: .ultraLight, design: .default))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: valueText)
            Text(captionText)
                .font(Df.captionFont)
                .foregroundStyle(Df.textTertiary(scheme))
        }
        .padding(.horizontal, Df.space5)
        .padding(.vertical, Df.space4)
        .frame(minWidth: 280, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: Df.radiusLarge)
                .fill(Df.surface(scheme))
                .shadow(color: Df.bevelShadow(scheme).opacity(0.4), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Df.radiusLarge)
                .strokeBorder(Df.bevelHighlight(scheme).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Instrumentation strip — diagnostics in plain sight

    private var instrumentationStrip: some View {
        HStack(spacing: Df.space5) {
            probeMetrics(label: "cpu", reading: cpu.reading)
            Divider().frame(height: 22)
            probeMetrics(label: "mem", reading: memory.reading)
            Spacer()
            Button {
                cpu.nudge()
                memory.nudge()
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

    private func probeMetrics<V>(label: String, reading: ProbeReading<V>) -> some View {
        HStack(spacing: Df.space3) {
            metric("name",   label)
            metric("ticks",  "\(reading.ticksSucceeded)/\(reading.ticksTotal)")
            metric("p50",    formatLatency(reading.latencyP50))
            metric("p95",    formatLatency(reading.latencyP95))
            metric("circuit", circuitLabel(reading.circuit))
            if let s = reading.staleness() {
                metric("age", String(format: "%.1fs", s))
            } else {
                metric("age", "—")
            }
            if reading.paused {
                metric("state", "paused")
            }
        }
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

    // MARK: - Per-probe display derivation

    /// CPU's Value is `Double?` (nil before first delta). Reading wraps that
    /// in another optional → `Double??`. Outer-nil = no successful tick yet;
    /// outer-some-inner-nil = first tick captured but no delta yet.
    private var cpuUnwrapped: Double? {
        guard case let .some(inner) = cpu.reading.value else { return nil }
        return inner
    }
    private var cpuValueText: String {
        guard let v = cpuUnwrapped else { return "—" }
        return String(format: "%.0f%%", v * 100)
    }

    /// Memory's Value is `Double` (always non-optional once the tick succeeds).
    private var memoryUnwrapped: Double? { memory.reading.value }
    private var memoryValueText: String {
        guard let v = memoryUnwrapped else { return "—" }
        return String(format: "%.0f%%", v * 100)
    }

    // MARK: - Shared formatting

    private func color<V>(percent: Double?, reading: ProbeReading<V>, cadence: Duration) -> Color {
        if reading.lastError != nil { return Df.critical }
        if reading.isStale(cadence: cadence) { return Df.uncertain }
        guard let v = percent else { return Df.textTertiary(scheme) }
        if v >= 0.85 { return Df.critical }
        if v >= 0.65 { return Df.uncertain }
        return Df.textPrimary(scheme)
    }

    private func caption<V>(for reading: ProbeReading<V>, cadence: Duration, valueIsAbsent: Bool) -> String {
        if let err = reading.lastError {
            return err.userFacing
        }
        if let s = reading.staleness(), s > cadence.seconds * 3 {
            return String(format: "stale %.0fs", s)
        }
        if valueIsAbsent { return "warming up…" }
        switch reading.circuit {
        case .closed: return "live"
        case .halfOpen(let n): return "recovering · \(n) probes left"
        case .open(let until):
            let dt = max(0, until.timeIntervalSinceNow)
            return String(format: "circuit open · retry in %.0fs", dt)
        }
    }

    private func circuitLabel(_ s: CircuitState) -> String {
        switch s {
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
