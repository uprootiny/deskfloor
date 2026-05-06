import Foundation
import Observation

/// Drives a `Probe` according to the Pulse contract: monotonic cadence, p50/p95
/// latency, circuit breaker with exponential backoff, occlusion pause/resume,
/// friendly error classification, AsyncStream lifecycle events.
///
/// One `ProbeRunner` per probe. Concurrency is contained via `@MainActor` on
/// the published reading (so SwiftUI reads it without bridging) and an
/// internal serial Task for the tick loop.
@MainActor
@Observable
final class ProbeRunner<P: Probe> {
    let probe: P

    /// What the View renders. Always non-nil and well-formed even before the
    /// first tick — `value` is just nil until then.
    private(set) var reading: ProbeReading<P.Value>

    /// Public lifecycle stream — diagnostics view subscribes; tests do too.
    let events: AsyncStream<ProbeEvent>

    // MARK: - Internals

    private let eventContinuation: AsyncStream<ProbeEvent>.Continuation
    private var loopTask: Task<Void, Never>?
    private var latencySamples: [Duration] = []
    private let latencyWindow = 32
    private let circuitFailureThreshold = 3
    private let circuitMaxBackoff: Duration = .seconds(60)
    private let halfOpenProbeCount = 2
    private let clock = ContinuousClock()

    // MARK: - Init

    init(probe: P) {
        self.probe = probe
        self.reading = ProbeReading(
            value: nil,
            lastSuccess: nil,
            lastError: nil,
            circuit: .closed,
            consecutiveFailures: 0,
            ticksTotal: 0,
            ticksSucceeded: 0,
            latencyP50: .zero,
            latencyP95: .zero,
            paused: true
        )
        var continuation: AsyncStream<ProbeEvent>.Continuation!
        self.events = AsyncStream { c in continuation = c }
        self.eventContinuation = continuation
    }

    // MARK: - Lifecycle

    /// Starts the tick loop. Idempotent — repeated calls do nothing.
    func start() {
        guard loopTask == nil else { return }
        reading.paused = false
        eventContinuation.yield(.resumed(name: probe.name))
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Stops the tick loop. Drops the in-flight tick *cooperatively* — the
    /// `Task.checkCancellation()` inside `runLoop` makes the next sleep return.
    func pause() {
        loopTask?.cancel()
        loopTask = nil
        reading.paused = true
        eventContinuation.yield(.paused(name: probe.name))
    }

    /// Force a sample on the next runloop pass — useful when a user explicitly
    /// asks for a refresh. No-op when paused.
    func nudge() {
        // Cancelling the loop's sleep makes it wake immediately; the loop
        // itself recreates the sleep on the next iteration.
        loopTask?.cancel()
        loopTask = nil
        if !reading.paused { start() }
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - The loop

    private func runLoop() async {
        // First tick fires immediately so the UI doesn't sit blank for a cadence.
        while !Task.isCancelled {
            await tickOnce()

            // Compute next sleep based on circuit state. Monotonic — we
            // measure how long the tick took and subtract from cadence so
            // we don't drift later and later.
            let nextSleep = sleepDurationAfterTick()
            do {
                try await clock.sleep(for: nextSleep)
            } catch {
                // Cancellation throws — exit cleanly.
                break
            }
        }
    }

    private func tickOnce() async {
        // Skip when circuit is open and the cool-off hasn't elapsed.
        if case .open(let until) = reading.circuit, until > Date() {
            return
        }

        let start = clock.now
        eventContinuation.yield(.tickStarted(name: probe.name, at: Date()))
        reading.ticksTotal += 1

        do {
            let value = try await probe.tick()
            let elapsed = clock.now - start
            recordLatency(elapsed)
            reading.value = value
            reading.lastSuccess = Date()
            reading.lastError = nil
            reading.ticksSucceeded += 1
            reading.consecutiveFailures = 0
            transitionOnSuccess()
            eventContinuation.yield(.tickSucceeded(name: probe.name, latency: elapsed))
        } catch let pe as ProbeError {
            handleFailure(pe, since: start)
        } catch {
            handleFailure(.underlying(error), since: start)
        }
    }

    private func handleFailure(_ pe: ProbeError, since start: ContinuousClock.Instant) {
        let elapsed = clock.now - start
        recordLatency(elapsed)
        reading.lastError = pe
        reading.consecutiveFailures += 1
        eventContinuation.yield(.tickFailed(name: probe.name, error: pe, latency: elapsed))
        transitionOnFailure(pe)
    }

    // MARK: - Circuit transitions

    private func transitionOnSuccess() {
        switch reading.circuit {
        case .closed:
            return
        case .halfOpen(let remaining):
            let next = remaining - 1
            if next <= 0 {
                reading.circuit = .closed
                eventContinuation.yield(.circuitClosed(name: probe.name))
            } else {
                reading.circuit = .halfOpen(attemptsRemaining: next)
            }
        case .open:
            // A success while open shouldn't happen (we skip the tick), but
            // be forgiving and consider the circuit recovered.
            reading.circuit = .closed
            eventContinuation.yield(.circuitClosed(name: probe.name))
        }
    }

    private func transitionOnFailure(_ pe: ProbeError) {
        // Permission errors don't drive the circuit — they're permanent until
        // the user fixes the entitlement. We back off generously.
        if pe.isPermanentUntilUserAction {
            let until = Date().addingTimeInterval(circuitMaxBackoff.seconds)
            reading.circuit = .open(until: until)
            eventContinuation.yield(.circuitOpened(name: probe.name, until: until))
            return
        }

        if reading.consecutiveFailures >= circuitFailureThreshold {
            // Exponential backoff: 2, 4, 8, …, capped.
            let exp = min(reading.consecutiveFailures - circuitFailureThreshold, 5)
            let secs = min(pow(2.0, Double(exp + 1)), circuitMaxBackoff.seconds)
            let until = Date().addingTimeInterval(secs)
            reading.circuit = .open(until: until)
            eventContinuation.yield(.circuitOpened(name: probe.name, until: until))
        }
    }

    private func sleepDurationAfterTick() -> Duration {
        switch reading.circuit {
        case .open(let until):
            // Sleep until the cool-off ends. The next iteration may transition
            // to half-open and try again.
            let secs = max(0.05, until.timeIntervalSinceNow)
            return .seconds(secs)
        case .halfOpen:
            // Probe at half rate while recovering.
            return probe.preferredCadence + probe.preferredCadence
        case .closed:
            return probe.preferredCadence
        }
    }

    // MARK: - Latency tracking

    private func recordLatency(_ d: Duration) {
        latencySamples.append(d)
        if latencySamples.count > latencyWindow {
            latencySamples.removeFirst(latencySamples.count - latencyWindow)
        }
        let sorted = latencySamples.sorted { $0 < $1 }
        if !sorted.isEmpty {
            reading.latencyP50 = sorted[sorted.count / 2]
            let p95Idx = max(0, Int(Double(sorted.count) * 0.95) - 1)
            reading.latencyP95 = sorted[min(p95Idx, sorted.count - 1)]
        }
    }
}
