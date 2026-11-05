import AppKit
import SwiftUI

/// Moves the map with a mouse as canvases do: the wheel zooms toward the pointer, and a drag with the
/// right button held pans, leaving the left button to click and select. A trackpad keeps its own ways,
/// two fingers to pan and a pinch to zoom, since its scrolling is smooth where a wheel's comes in steps.
///
/// It finds the scroll view the map is drawn in from inside it, with ``MapScrollReader``, and watches
/// the window's events for those over the map: it answers a wheel's and passes a trackpad's on, and holds
/// a right press until it knows whether it is a drag, which pans, or a click, which it hands back on
/// release so a box's menu still opens.
@MainActor
final class MapScroller {
    /// The scroll view the map is drawn in, once the reader has found it.
    weak var scrollView: NSScrollView?
    /// What to do with a wheel's zoom: the scale to zoom to, from the one the map shows now.
    var zoom: ((CGFloat) -> Void)?
    /// The scale the map shows now, fitted or chosen, which a wheel's zoom starts from.
    var scale: CGFloat = 1
    /// The room the canvas leaves past the figure on each side, which does not scale with it.
    var margin: CGSize = .zero
    private var watch: Any?
    private var pressWatch: Any?
    /// A right press over the map not yet known to be a drag or a click: where it was, the last place a
    /// drag reached, and what is needed to hand it back as a click.
    private var press: Press?
    /// Whether the right press in progress has moved far enough to pan.
    private var isPanning = false
    /// `true` while a held press is handed back, so the watch lets it through.
    private var isReplaying = false

    /// A right press, held as plain values so it can be handed back when it proves to be a click.
    private struct Press {
        var window: Int
        var start: NSPoint
        var last: NSPoint
        var modifiers: UInt
        var timestamp: TimeInterval
        var eventNumber: Int
        var clickCount: Int
    }

    /// How far a right press moves before it pans rather than clicks, in points.
    private static let slop: CGFloat = 3

    /// The most a single step of the wheel zooms by.
    private static let step: CGFloat = 1.1

    /// Starts answering the wheel and the right button over the map; starting again does nothing.
    func start() {
        guard watch == nil else { return }
        pressWatch = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseDragged, .rightMouseUp]) { [weak self] event in
            // Only plain values cross into the main actor; the event itself stays here.
            let type = event.type
            let number = event.windowNumber
            let location = event.locationInWindow
            let modifiers = event.modifierFlags.rawValue
            let timestamp = event.timestamp
            let eventNumber = event.eventNumber
            let clickCount = event.clickCount
            let answered = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                switch type {
                case .rightMouseDown:
                    return self.pressed(at: location, inWindow: number,
                                        press: Press(window: number, start: location, last: location, modifiers: modifiers,
                                                     timestamp: timestamp, eventNumber: eventNumber, clickCount: clickCount))
                case .rightMouseDragged: return self.dragged(to: location)
                default: return self.released()
                }
            }
            return answered ? nil : event
        }
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

    /// Stops answering the wheel and the right button.
    func stop() {
        if let watch { NSEvent.removeMonitor(watch) }
        if let pressWatch { NSEvent.removeMonitor(pressWatch) }
        watch = nil
        pressWatch = nil
        if isPanning { NSCursor.pop() }
        press = nil
        isPanning = false
    }

    /// Holds a right press over the map until it proves to be a drag or a click.
    ///
    /// - Parameters:
    ///   - location: Where the pointer is, in the window's coordinates.
    ///   - number: The window the event is for.
    ///   - press: The press, as plain values.
    /// - Returns: `true` when the press was over the map and is held; a press handed back is let through.
    private func pressed(at location: NSPoint, inWindow number: Int, press: Press) -> Bool {
        guard !isReplaying, let scrollView, let window = scrollView.window, number == window.windowNumber else { return false }
        let clip = scrollView.contentView
        guard clip.bounds.contains(clip.convert(location, from: nil)) else { return false }
        self.press = press
        isPanning = false
        return true
    }

    /// Pans the map with a held right press once it has moved past the slop.
    ///
    /// - Parameter location: Where the pointer is now, in the window's coordinates.
    /// - Returns: `true` while a held press is being answered.
    private func dragged(to location: NSPoint) -> Bool {
        guard var press else { return false }
        if !isPanning {
            guard hypot(location.x - press.start.x, location.y - press.start.y) >= Self.slop else { return true }
            isPanning = true
            NSCursor.closedHand.push()
        }
        // The window's y runs up and a pan's down, so the map follows the pointer.
        pan(by: CGSize(width: location.x - press.last.x, height: press.last.y - location.y))
        press.last = location
        self.press = press
        return true
    }

    /// Ends a held right press: a drag is done, and a click is handed back to the view under it, so a
    /// box's menu opens on release.
    ///
    /// - Returns: `true` when the release belonged to a held press.
    private func released() -> Bool {
        guard let press else { return false }
        self.press = nil
        if isPanning {
            isPanning = false
            NSCursor.pop()
            return true
        }
        guard let window = scrollView?.window,
              let down = NSEvent.mouseEvent(with: .rightMouseDown, location: press.start,
                                            modifierFlags: NSEvent.ModifierFlags(rawValue: press.modifiers), timestamp: press.timestamp,
                                            windowNumber: press.window, context: nil, eventNumber: press.eventNumber,
                                            clickCount: press.clickCount, pressure: 1) else { return true }
        isReplaying = true
        window.sendEvent(down)
        isReplaying = false
        return true
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
        // pointer is brought back under it. Only the figure scales, not the room around it.
        let margin = self.margin
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView = self.scrollView else { return }
            self.scroll(to: CGPoint(x: margin.width + (inClip.x - margin.width) * factor - pointer.x,
                                    y: margin.height + (inClip.y - margin.height) * factor - pointer.y), in: scrollView)
        }
        return true
    }

    /// Centers the canvas on the figure once it has laid out again, as a new figure opens.
    func center() {
        // The figure lays out at its new size on the next pass, and the canvas with it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView = self.scrollView else { return }
            let clip = scrollView.contentView.bounds.size
            let document = scrollView.documentView?.frame.size ?? .zero
            self.scroll(to: CGPoint(x: (document.width - clip.width) / 2, y: (document.height - clip.height) / 2), in: scrollView)
        }
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
