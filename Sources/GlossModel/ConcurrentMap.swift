import Foundation


/// Transforms each element on as many threads as there are cores, keeping the elements' order.
///
/// - Parameters:
///   - elements: The elements.
///   - transform: What to make of each one; it runs on several threads at once, so it must touch no
///     shared state it changes.
/// - Returns: The results, in the elements' order.
package func concurrentMap<Element: Sendable, Result: Sendable>(_ elements: [Element], _ transform: @Sendable (Element) -> Result) -> [Result] {
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
