# Pan the map like a canvas, with the right button

A fitted figure had nothing to scroll, so a pan sprang back to the middle, and the left button both selected and panned. Now the map pans freely past its edges, a strip always in view, and a right-button drag pans while the left only clicks.

## Room to pan past the figure

``MapPaneView`` pads the canvas by about a pane on every side, so a pan meets its limit only when just a strip of the figure is left. A new figure still opens fitted and centered.

### ``MapPaneView``

Its doc now says the canvas reaches a pane past the figure, so it pans as a canvas does.

### ``MapPaneView/kept``

How much of the figure a pan leaves in view, so the reader can never lose it entirely.

### ``MapPaneView/margin(for:)``

Sizes the room past each edge from the pane, so panning feels the same in a narrow pane and a wide one.

### ``MapPaneView/body``

Pads the canvas with that room, drops the left-button drag, and recenters whenever a new figure arrives or the reader fits or centers it.

### ``MapPaneView/dragged``

Gone with the left-button drag it tracked.

### ``MapScroller/margin``

Kept so a wheel's zoom scales only the figure, not the room around it, and the point under the pointer stays put.

### ``MapScroller/zoomed(by:at:inWindow:)``

Leaves the margin out of the scaling, which the room past the figure would otherwise throw off.

### ``MapScroller/center()``

Added because a pan can now leave the canvas off center, which a new figure should not inherit.

## The right button pans, the left one clicks

``MapScroller`` holds a right press over the map until it knows what it is: a drag pans, and a click is handed back on release, so a box's menu still opens. The left button no longer pans, so a click never turns into a small pan.

### ``MapScroller``

Its doc now says a right-button drag pans and a right click is handed back for the menu.

### ``MapScroller/start()``

Also watches the right button, since a SwiftUI gesture cannot tell a right drag from the box menu's press.

### ``MapScroller/stop()``

Stops that watch too, and puts the cursor back if a pan was cut short.

### ``MapScroller/pressWatch``

The right button's watch, kept apart from the wheel's so each stops cleanly.

### ``MapScroller/press``

The right press being held, until it proves to be a drag or a click.

### ``MapScroller/isPanning``

Set once a press moves past the slop, so a small wobble still counts as a click.

### ``MapScroller/isReplaying``

Lets a handed-back press through the watch rather than holding it again.

### ``MapScroller/slop``

Three points, enough to tell a steady click from a drag.

### ``MapScroller/pressed(at:inWindow:press:)``

Holds a right press only over the map, so the list and the details keep their own right clicks.

### ``MapScroller/dragged(to:)``

Pans by the pointer's movement in the window, so the map follows the hand.

### ``MapScroller/released()``

Hands a right click back as a fresh press, so a box's menu opens on release instead of being lost.

### ``MapScroller/Press/window``

The window the press was in, which a handed-back press must name.

### ``MapScroller/Press/start``

Where the press began, both for the slop and for the press handed back.

### ``MapScroller/Press/last``

Where the drag last reached, so each step pans only by its own movement.

### ``MapScroller/Press/modifiers``

Kept so a handed-back press carries the keys held with it.

### ``MapScroller/Press/timestamp``

Kept so a handed-back press reads as the one the reader made.

### ``MapScroller/Press/eventNumber``

Kept for the same reason, as AppKit numbers each press.

### ``MapScroller/Press/clickCount``

Kept so a handed-back press counts its clicks as the reader did.

## One click back to the middle

A figure panned far off needs a quick way back, so the zoom control gains a button that centers it. Fitting the figure again centers it too.

### ``MagnifierView``

Its doc now names the centering button beside the zoom.

### ``MagnifierView/recenter``

Added so the control can center the figure without knowing the scroll view that holds it.

### ``MagnifierView/body``

Leads with the centering button, set off from the zoom by a divider, and says that fitting centers too.
