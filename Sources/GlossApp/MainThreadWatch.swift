import Foundation
import GlossCore

/// Notices when the main thread cannot respond, whatever kept it busy, a view's body included, and
/// logs for how long as `main thread blocked`, so a choppy moment shows in the timing log beside the
/// selection and the phases around it.
///
/// A thread of its own asks the main thread to answer every 50 milliseconds, waiting for one answer
/// before asking again, and logs an answer that comes more than three frames late.
final class MainThreadWatch: @unchecked Sendable {
    /// How late an answer may be before it is logged.
    static let threshold = Duration.milliseconds(50)
    /// The watch the app keeps running.
    private static let shared = MainThreadWatch()

    private let queue = DispatchQueue(label: "gloss.main-thread-watch", qos: .utility)
    private let lock = NSLock()
    // Guarded by `lock`: whether a question is out that the main thread has not answered yet.
    private var waiting = false
    private var timer: DispatchSourceTimer?

    /// Starts the app's watch; starting it again does nothing.
    static func start() {
        shared.start()
    }

    /// Starts asking the main thread to answer.
    private func start() {
        lock.withLock {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler { [self] in ask() }
            timer.resume()
            self.timer = timer
        }
    }

    /// Asks the main thread to answer, unless it has yet to answer the last question.
    private func ask() {
        guard lock.withLock({ () -> Bool in
            defer { waiting = true }
            return !waiting
        }) else { return }
        let asked = ContinuousClock.now
        DispatchQueue.main.async { [self] in
            let late = ContinuousClock.now - asked
            lock.withLock { waiting = false }
            if late >= Self.threshold { Timing.note("main thread blocked", duration: late) }
        }
    }
}
