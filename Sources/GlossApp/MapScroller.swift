import AppKit
import SwiftUI

/// Moves the map with a mouse as canvases do: the wheel zooms toward the pointer, and a drag pans. A
/// trackpad keeps its own ways, two fingers to pan and a pinch to zoom, since its scrolling is smooth
/// where a wheel's comes in steps.
///
/// It finds the scroll view the map is drawn in from inside it, with ``MapScrollReader``, and watches
/// the window's scroll events for those over the map, answering a wheel's and passing a trackpad's on.
@MainActor
final class MapScroller {
    /// The scroll view the map is drawn in, once the reader has found it.
    weak var scrollView: NSScrollView?
    /// What to do with a wheel's zoom: the scale to zoom to, from the one the map shows now.
    var zoom: ((CGFloat) -> Void)?
    /// The scale the map shows now, fitted or chosen, which a wheel's zoom starts from.
    var scale: CGFloat = 1
    private var watch: Any?

    /// The most a single step of the wheel zooms by.
    private static let step: CGFloat = 1.1

    /// Starts answering the wheel over the map; starting again does nothing.
    func start() {
        guard watch == nil else { return }
        watch = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Only plain values cross into the main actor; the event itself stays here.
            let isWheel = !event.hasPreciseScrollingDeltas
            let away = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let number = event.windowNumber
            let location = event.locationInWindow
            guard isWheel, away != 0 else { return event }
            let answered = MainActor.assumeIsolated { () -> Bool in
                self?.zoomed(by: away, at: location, inWindow: number) ?? false
            }
            return answered ? nil : event
        }
    }

    /// Stops answering the wheel.
    func stop() {
        if let watch { NSEvent.removeMonitor(watch) }
        watch = nil
    }

    /// Zooms toward a point for a turn of the wheel over the map, keeping the point under the pointer.
    ///
    /// - Parameters:
    ///   - away: How far the wheel turned away from the reader, in its steps; toward the reader is
    ///     negative and zooms out.
    ///   - location: Where the pointer is, in the window's coordinates.
    ///   - number: The window the event is for.
    /// - Returns: `true` when the wheel was over the map and zoomed it.
    private func zoomed(by away: CGFloat, at location: NSPoint, inWindow number: Int) -> Bool {
        guard let scrollView, let window = scrollView.window, let zoom else { return false }
        // A wheel's event names the window under the pointer; one posted without a window, as some mouse
        // utilities post them, gives the pointer on the screen instead.
        let inWindow: NSPoint
        if number == window.windowNumber {
            inWindow = location
        } else if number == 0 {
            inWindow = window.convertPoint(fromScreen: location)
        } else {
            return false
        }
        let clip = scrollView.contentView
        let inClip = clip.convert(inWindow, from: nil)
        guard clip.bounds.contains(inClip) else { return false }
        let target = MapPaneView.clamp(scale * pow(Self.step, max(-3, min(3, away))))
        let factor = target / scale
        // Where the pointer is in the clip view, so the point of the map under it can be put back there.
        let origin = clip.bounds.origin
        let pointer = CGPoint(x: inClip.x - origin.x, y: inClip.y - origin.y)
        zoom(target)
        // Several steps can come before the map draws again, so each goes on from the last.
        scale = target
        // The map lays out again at its new scale on the next pass; then the point that was under the
        // pointer is brought back under it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView = self.scrollView else { return }
            self.scroll(to: CGPoint(x: inClip.x * factor - pointer.x, y: inClip.y * factor - pointer.y), in: scrollView)
        }
        return true
    }

    /// Pans the map by a drag's movement, the map following the pointer.
    ///
    /// - Parameter delta: How far the pointer moved since the last call, in points, down and to the right
    ///   positive.
    func pan(by delta: CGSize) {
        guard let scrollView else { return }
        let origin = scrollView.contentView.bounds.origin
        let flipped = scrollView.documentView?.isFlipped ?? true
        scroll(to: CGPoint(x: origin.x - delta.width, y: flipped ? origin.y - delta.height : origin.y + delta.height), in: scrollView)
    }

    /// Scrolls to a point, held within what the map can scroll to.
    ///
    /// - Parameters:
    ///   - point: The clip view's new origin.
    ///   - scrollView: The scroll view.
    private func scroll(to point: CGPoint, in scrollView: NSScrollView) {
        let clip = scrollView.contentView
        let document = scrollView.documentView?.frame.size ?? .zero
        let limit = CGPoint(x: max(0, document.width - clip.bounds.width), y: max(0, document.height - clip.bounds.height))
        clip.scroll(to: CGPoint(x: min(max(0, point.x), limit.x), y: min(max(0, point.y), limit.y)))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Hands the scroll view a view is drawn in to a ``MapScroller``, once the view is in it.
struct MapScrollReader: NSViewRepresentable {
    /// The scroller to hand the scroll view to.
    var scroller: MapScroller

    /// Makes the view that finds its scroll view.
    ///
    /// - Parameter context: The representable's context, unused.
    /// - Returns: A view that hands over its scroll view once it is in one.
    func makeNSView(context: Context) -> NSView {
        Finder(scroller: scroller)
    }

    /// Hands over the scroll view again, in case the view has moved into another.
    ///
    /// - Parameters:
    ///   - nsView: The view.
    ///   - context: The representable's context, unused.
    func updateNSView(_ nsView: NSView, context: Context) {
        if let scrollView = nsView.enclosingScrollView { scroller.scrollView = scrollView }
    }

    /// Hands over the scroll view it lands in.
    final class Finder: NSView {
        private let scroller: MapScroller

        /// Makes a view that hands over its scroll view.
        ///
        /// - Parameter scroller: The scroller to hand it to.
        init(scroller: MapScroller) {
            self.scroller = scroller
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scrollView = enclosingScrollView { scroller.scrollView = scrollView }
        }
    }
}
