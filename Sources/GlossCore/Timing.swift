import Foundation
#if canImport(os)
import os
#endif

/// How long gloss's work takes, so a slow phase can be found and a change that slows one seen.
///
/// The work that can be slow measures itself, at the model's entry points: reading, building, and
/// comparing an interface, and arranging, drawing, and searching it. Whatever calls them, a view
/// included, is timed without saying so; the calls cheap enough to make thousands of times a frame
/// are not measured, since measuring would cost more than they do.
///
/// Each phase measured is an interval under Points of Interest in Instruments, a debug line in the
/// unified log under the `gloss` subsystem (`log stream --level debug --predicate 'subsystem == "gloss"'`),
/// and, with `GLOSS_TIMING` set in the environment, a line on standard error. ``record(_:)`` collects
/// the phases of some work as well, which is how `gloss bench` reports them.
public enum Timing {
    /// One phase measured: what it was and how long it took.
    public struct Sample: Sendable, Equatable {
        /// The phase, such as `parse` or `layout`.
        public var name: String
        /// What the phase worked on, such as a file or a level, or empty.
        public var detail: String
        /// How long it took.
        public var duration: Duration
    }

    #if canImport(os)
    private static let signposter = OSSignposter(subsystem: "gloss", category: .pointsOfInterest)
    private static let logger = Logger(subsystem: "gloss", category: "timing")
    #endif
    /// Whether phases are written to standard error as well, as `GLOSS_TIMING` asks.
    private static let writesToStandardError = ProcessInfo.processInfo.environment["GLOSS_TIMING"] != nil
    private static let lock = NSLock()
    // Guarded by `lock`: the samples of the work ``record(_:)`` runs, or `nil` while nothing records.
    nonisolated(unsafe) private static var recorded: [Sample]?

    /// Runs some work and measures it.
    ///
    /// - Parameters:
    ///   - name: The phase, which names the interval in Instruments.
    ///   - detail: What the phase works on, read only once the work is done.
    ///   - work: The work.
    /// - Returns: What the work returns.
    /// - Throws: What the work throws, once it is measured.
    public static func measure<T>(_ name: StaticString, _ detail: @autoclosure () -> String = "",
                                  _ work: () throws -> T) rethrows -> T {
        let phase = begin(name)
        defer { end(phase, detail()) }
        return try work()
    }

    /// A phase under way, from ``begin(_:)`` until ``end(_:_:)``.
    public struct Phase {
        /// The phase, which names the interval in Instruments.
        fileprivate let name: StaticString
        /// When it began.
        fileprivate let start: ContinuousClock.Instant
        #if canImport(os)
        /// Its interval in Instruments.
        fileprivate let interval: OSSignpostIntervalState
        #endif
    }

    /// Starts measuring a phase, for a function that measures itself from its first line:
    /// `let phase = Timing.begin("reach"); defer { Timing.end(phase, id) }`.
    ///
    /// - Parameter name: The phase, which names the interval in Instruments.
    /// - Returns: The phase, to pass to ``end(_:_:)``.
    public static func begin(_ name: StaticString) -> Phase {
        #if canImport(os)
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
        return Phase(name: name, start: ContinuousClock.now, interval: interval)
        #else
        return Phase(name: name, start: ContinuousClock.now)
        #endif
    }

    /// Ends a phase and reports it.
    ///
    /// - Parameters:
    ///   - phase: The phase ``begin(_:)`` started.
    ///   - detail: What the phase worked on, read only now.
    public static func end(_ phase: Phase, _ detail: @autoclosure () -> String = "") {
        let duration = ContinuousClock.now - phase.start
        #if canImport(os)
        signposter.endInterval(phase.name, phase.interval)
        #endif
        report(Sample(name: "\(phase.name)", detail: detail(), duration: duration))
    }

    /// Marks a moment, such as a selection, so the phases after it read against it: an event in
    /// Instruments and a line wherever phases go.
    ///
    /// - Parameters:
    ///   - name: What happened.
    ///   - detail: What it happened to.
    public static func event(_ name: StaticString, _ detail: @autoclosure () -> String = "") {
        #if canImport(os)
        signposter.emitEvent(name)
        #endif
        report(Sample(name: "\(name)", detail: detail(), duration: .zero), isEvent: true)
    }

    /// Reports a phase measured some other way, such as how long the main thread could not respond.
    ///
    /// - Parameters:
    ///   - name: The phase.
    ///   - detail: What it worked on, or empty.
    ///   - duration: How long it took.
    public static func note(_ name: String, _ detail: String = "", duration: Duration) {
        report(Sample(name: name, detail: detail, duration: duration))
    }

    /// Runs some work and collects every phase measured while it runs, on any thread.
    ///
    /// - Parameter work: The work.
    /// - Returns: What the work returns, and the phases in the order they finished.
    /// - Throws: What the work throws.
    public static func record<T>(_ work: () throws -> T) rethrows -> (result: T, samples: [Sample]) {
        lock.withLock { recorded = [] }
        let result = try work()
        let samples = lock.withLock { () -> [Sample] in
            defer { recorded = nil }
            return recorded ?? []
        }
        return (result, samples)
    }

    /// Writes one phase or moment wherever they go.
    ///
    /// - Parameters:
    ///   - sample: The phase.
    ///   - isEvent: `true` for a moment, which has no duration to write and is not collected.
    private static func report(_ sample: Sample, isEvent: Bool = false) {
        if !isEvent { lock.withLock { recorded?.append(sample) } }
        let time = isEvent ? "" : String(format: " %.2f ms", sample.duration.milliseconds)
        let line = sample.name + time + (sample.detail.isEmpty ? "" : " " + sample.detail)
        #if canImport(os)
        logger.debug("\(line, privacy: .public)")
        #endif
        if writesToStandardError { FileHandle.standardError.write(Data(("gloss timing: " + line + "\n").utf8)) }
    }
}

extension Duration {
    /// The duration in milliseconds, fractions included.
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}

/// Transforms each element on as many threads as there are cores, keeping the elements' order.
///
/// - Parameters:
///   - elements: The elements.
///   - transform: What to make of each one; it runs on several threads at once, so it must touch no
///     shared state it changes.
/// - Returns: The results, in the elements' order.
func concurrentMap<Element: Sendable, Result: Sendable>(_ elements: [Element], _ transform: @Sendable (Element) -> Result) -> [Result] {
    let slots = Slots<Result>(count: elements.count)
    defer { slots.buffer.deallocate() }
    DispatchQueue.concurrentPerform(iterations: elements.count) { slots.buffer[$0] = transform(elements[$0]) }
    return slots.buffer.map { $0! }
}

/// The results of ``concurrentMap(_:_:)``, one slot per element, each written by one thread only.
private final class Slots<Result>: @unchecked Sendable {
    /// The slots, empty until their element is transformed.
    let buffer: UnsafeMutableBufferPointer<Result?>

    /// Makes empty slots.
    ///
    /// - Parameter count: How many.
    init(count: Int) {
        buffer = .allocate(capacity: count)
        buffer.initialize(repeating: nil)
    }
}
