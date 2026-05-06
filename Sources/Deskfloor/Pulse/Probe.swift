import Foundation

/// One unit of live state for the Pulse surface.
///
/// A Probe knows *how* to take one sample. It does not know about cadence,
/// retries, circuit breakers, occlusion, or UI — that is `ProbeRunner`'s job.
/// This split is what makes the pattern reusable: every Pulse tile
/// (CPU, RAM, disk, fleet, CI, agents, …) implements `Probe` once, and gets
/// instrumentation, backoff, and pause-on-occlusion for free.
protocol Probe: Sendable {
    /// The shape of the value this probe yields. Equatable so the runner can
    /// suppress no-op UI updates.
    associatedtype Value: Sendable & Equatable

    /// Stable identifier used in events, logs, and diagnostics. Lower-kebab.
    var name: String { get }

    /// Cadence when healthy. Real cadence may stretch under backoff or shrink
    /// nowhere — we never tick *faster* than this.
    var preferredCadence: Duration { get }

    /// Take exactly one sample. May throw `ProbeError` for known classes.
    /// Anything else is wrapped as `.unknown` with the call site preserved.
    func tick() async throws -> Value
}

/// Errors a probe is expected to recognize and classify, so the runner can
/// surface friendly messages and decide whether to keep retrying.
enum ProbeError: Error, Sendable {
    /// Sandbox / entitlement / permission denied. Backoff is pointless —
    /// surface a "fix this once" affordance and stop hammering.
    case permissionDenied(detail: String)
    /// The data source returned a value that fails sanity (NaN, negative, etc.).
    /// Treat as transient.
    case sanityCheckFailed(detail: String)
    /// Underlying call failed in a way we don't classify yet.
    case underlying(Error)

    var isPermanentUntilUserAction: Bool {
        if case .permissionDenied = self { return true }
        return false
    }

    var userFacing: String {
        switch self {
        case .permissionDenied(let d): return "permission denied — \(d)"
        case .sanityCheckFailed(let d): return "bad sample — \(d)"
        case .underlying(let e):       return String(describing: e)
        }
    }
}

/// Steady-state reading the View consumes. Always represents the *latest*
/// known good value plus metadata describing how trustworthy that value is.
struct ProbeReading<Value: Sendable & Equatable>: Sendable, Equatable {
    var value: Value?
    var lastSuccess: Date?
    var lastError: ProbeError?
    var circuit: CircuitState
    var consecutiveFailures: Int
    var ticksTotal: Int
    var ticksSucceeded: Int
    var latencyP50: Duration
    var latencyP95: Duration
    var paused: Bool

    static func == (lhs: ProbeReading, rhs: ProbeReading) -> Bool {
        lhs.value == rhs.value &&
        lhs.lastSuccess == rhs.lastSuccess &&
        lhs.circuit == rhs.circuit &&
        lhs.consecutiveFailures == rhs.consecutiveFailures &&
        lhs.ticksTotal == rhs.ticksTotal &&
        lhs.ticksSucceeded == rhs.ticksSucceeded &&
        lhs.paused == rhs.paused
    }

    /// Time since the last successful tick. nil when never succeeded.
    func staleness(now: Date = Date()) -> TimeInterval? {
        guard let last = lastSuccess else { return nil }
        return now.timeIntervalSince(last)
    }

    /// True when no value has yet arrived OR the last one is older than 3× cadence.
    func isStale(now: Date = Date(), cadence: Duration) -> Bool {
        guard let last = lastSuccess else { return true }
        return now.timeIntervalSince(last) > cadence.seconds * 3
    }
}

enum CircuitState: Sendable, Equatable {
    case closed
    case halfOpen(attemptsRemaining: Int)
    case open(until: Date)

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}

/// Lifecycle event emitted on the runner's AsyncStream — for the diagnostics
/// view, for tracing, for tests. Never carries the Probe.Value (which would
/// force the type into the stream); just enumerates the transitions worth
/// recording.
enum ProbeEvent: Sendable {
    case tickStarted(name: String, at: Date)
    case tickSucceeded(name: String, latency: Duration)
    case tickFailed(name: String, error: ProbeError, latency: Duration)
    case circuitOpened(name: String, until: Date)
    case circuitHalfOpen(name: String)
    case circuitClosed(name: String)
    case paused(name: String)
    case resumed(name: String)
}

/// Tiny conversion so callers can ask `cadence.seconds` instead of
/// `Double(cadence.components.seconds) + Double(cadence.components.attoseconds) / 1e18`.
extension Duration {
    var seconds: Double {
        let comps = self.components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
