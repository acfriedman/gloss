# Zoom with the wheel and drag to pan the map

With a mouse the map could only scroll; zooming took the magnifier or the keyboard, and moving around took the scroll bars. The wheel now zooms toward the pointer and a drag pans, as canvases do, while a trackpad keeps two fingers to pan and a pinch to zoom.

## Answer the wheel and the drag

### ``MapScroller``

New: finds the scroll view the map is drawn in and watches the window's scroll events over it. A wheel's steps zoom toward the pointer, each step going on from the last, and the point under the pointer stays there; a trackpad's smooth scrolling passes on and pans as before. It pans by a drag's movement too, held within what the map can scroll to.

### ``MapScrollReader``

New: hands the scroll view the map is drawn in to the scroller, from inside it.

### ``MapPaneView``

Gives the map a scroller, tells it the scale the map shows, lets it set a new one, and pans by any drag on the map, the cursor a closed hand while it does; a click without moving still selects.
