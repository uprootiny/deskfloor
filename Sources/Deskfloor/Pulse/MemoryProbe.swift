import Darwin
import Foundation

/// Mach `host_statistics64(HOST_VM_INFO64)` → page-count counters
/// (active, inactive, wire, free, compressor, …). Page count × page size →
/// bytes; bytes / total physical → utilization fraction.
///
/// "Memory used" here matches Activity Monitor's "Memory Used" definition:
///     used = active + wired + compressor   (in pages)
///
/// We do NOT count `inactive` (recently-touched but evictable) because that's
/// the OS's slack, not the user's pressure. We do NOT count `free` (it's
/// available). `speculative` is OS prefetch — also not user pressure.
///
/// Disruption-tolerant on three fronts:
///   1. Total physical memory is read once at init from ProcessInfo (cheap +
///      stable). The pageSize comes from getpagesize() — POSIX, always
///      available, no entitlement.
///   2. Computed utilization outside [0, 1.5] is treated as a sanity failure
///      (never a hard crash). 1.5 is the high cap because compression can
///      briefly push the visible "used" past 100% before the page-out catches
///      up; we clamp to 1.0 for display but flag larger values as suspicious.
///   3. KERN_FAILURE → permissionDenied so the runner backs off generously
///      instead of hammering.
actor MemoryProbe: Probe {
    typealias Value = Double  // 0…1 memory pressure

    let name = "memory"
    let preferredCadence: Duration = .seconds(2)

    private let pageSize: UInt64
    private let totalPhysicalBytes: UInt64

    init() {
        self.pageSize = UInt64(getpagesize())
        self.totalPhysicalBytes = ProcessInfo.processInfo.physicalMemory
    }

    func tick() async throws -> Double {
        let snap = try Self.takeVMSnapshot()
        let usedPages = UInt64(snap.active) + UInt64(snap.wire) + snap.compressor
        let usedBytes = usedPages * pageSize
        let pct = Double(usedBytes) / Double(totalPhysicalBytes)
        guard (0.0 ... 1.5).contains(pct) else {
            throw ProbeError.sanityCheckFailed(
                detail: String(format: "computed usage %.3f outside [0, 1.5]", pct)
            )
        }
        return min(pct, 1.0)
    }

    // MARK: - Snapshot

    private struct VMSnap: Sendable {
        let active: UInt32
        let inactive: UInt32
        let wire: UInt32
        let free: UInt32
        let compressor: UInt64
    }

    private static func takeVMSnapshot() throws -> VMSnap {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        switch result {
        case KERN_SUCCESS:
            return VMSnap(
                active: info.active_count,
                inactive: info.inactive_count,
                wire: info.wire_count,
                free: info.free_count,
                compressor: UInt64(info.compressor_page_count)
            )
        default:
            throw ProbeError.permissionDenied(
                detail: "host_statistics64 returned \(result)"
            )
        }
    }
}
