# Expand one box in a focus, rather than the whole depth

A reach stops at a depth, and the only way past a box marked "+4 below" was to draw every type a step deeper. A reader can now follow one type further: expanding a box draws its own next step and no other's, and what it draws can be expanded in turn.

## Grow a reach past its depth at chosen types

``Atlas/reach(from:toward:depth:minimumRank:budget:expanding:)`` takes the types the reader expanded and draws each one's next step on its own side, past the depth, then the next step of any of those expanded too. ``Reach`` says what waits past each type at its frontier, as a ``Reach/Beyond``, and which types it expanded, so the map can offer the next step and its fold. The count is no longer written into the box's detail as well, since the pill on the edge already says how many and which way.

## Expand and fold from the map

``MapBoxView`` puts an ``ExpandPillView`` on the edge a box's next step waits past, its count on it, and a fold pill on a box already expanded; its menu does the same. ``MapCanvasView`` hands each box what its reach says about it. ``Workspace`` keeps each tab's expanded types, in its ``Workspace/Tab``, passes them to the reach through the ``Workspace/DrawingRequest``, and folds them all when the focus moves to another type or mode.
