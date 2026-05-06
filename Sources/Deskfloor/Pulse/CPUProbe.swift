import Darwin
import Foundation

/// Mach `host_statistics(HOST_CPU_LOAD_INFO)` → cumulative tick counters
/// (user, system, idle, nice). Two snapshots → one usage percent over the
/// interval between them.
///
/// Disruption-tolerant on three fronts:
///   1. First tick has no previous snapshot → returns `nil` cleanly (the
///      runner records this as a successful tick of an absent value, which
///      is what the View wants to render as "—" rather than 0%).
///   2. delta_total == 0 (system was suspended between ticks, or the
///      counters didn't move) → returns `nil` rather than NaN.
///   3. KERN_FAILURE → throws `.permissionDenied`. Sandbox / entitlement
///      class — backoff won't help; the runner pauses appropriately.
///
/// This actor is what serializes access to the previous-snapshot cache, so
/// even if the runner double-fires (it shouldn't), we don't race.
actor CPUProbe: Probe {
    typealias Value = Double?  // 0…1 utilization, or nil before first delta

    let name = "cpu"
    let preferredCadence: Duration = .seconds(2)

    private var previous: CPULoadSnapshot?

    func tick() async throws -> Double? {
        let snap = try Self.takeSnapshot()
        defer { self.previous = snap }
        guard let prev = previous else { return nil }
        return Self.utilization(prev: prev, curr: snap)
    }

    // MARK: - Snapshot

    private struct CPULoadSnapshot: Sendable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private static func takeSnapshot() throws -> CPULoadSnapshot {
        // Apple's HOST_CPU_LOAD_INFO_COUNT macro isn't bridged to Swift; compute it
        // the same way the C header does: layout-of-struct / layout-of-element.
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        switch result {
        case KERN_SUCCESS:
            return CPULoadSnapshot(
                user:   info.cpu_ticks.0,
                system: info.cpu_ticks.1,
                idle:   info.cpu_ticks.2,
                nice:   info.cpu_ticks.3
            )
        default:
            // KERN_FAILURE typically signals sandbox / no-entitlement.
            // Other kernels return rare codes — we lump them as permission so
            // the runner picks the slow-backoff path that doesn't hammer.
            throw ProbeError.permissionDenied(
                detail: "host_statistics returned \(result)"
            )
        }
    }

    /// Compute utilization as `1 - (delta_idle / delta_total)`. Range [0, 1].
    /// Returns nil for degenerate intervals so the caller doesn't display NaN.
    private static func utilization(prev: CPULoadSnapshot, curr: CPULoadSnapshot) -> Double? {
        let deltaUser   = Int64(curr.user)   - Int64(prev.user)
        let deltaSystem = Int64(curr.system) - Int64(prev.system)
        let deltaIdle   = Int64(curr.idle)   - Int64(prev.idle)
        let deltaNice   = Int64(curr.nice)   - Int64(prev.nice)
        let total = deltaUser + deltaSystem + deltaIdle + deltaNice
        guard total > 0 else { return nil }   // suspended interval, or counters wrapped
        let busy = Double(total - deltaIdle)
        let pct = busy / Double(total)
        // Sanity-check: any value outside [0, 1] is a wraparound or a bug.
        guard (0.0 ... 1.0).contains(pct) else { return nil }
        return pct
    }
}
