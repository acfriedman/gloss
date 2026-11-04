# Click the map's empty ground to go back to the level's page

Selecting a type on the Changes level left no way back to the story but Back. A canvas clears its selection when you click between its objects, so the map does too.

## Clear the selection on the map's ground

``Workspace/clickedBackground()`` takes a click on the map's empty ground back to the level's own page: the story at the changes level, a module's or folder's page at its level, and the overview at the widest. In a focus it unpins the pinned type instead, since the focus is the place. The step is a place in history, so Back returns to the type. ``MapPaneView`` hands it the click after any box's own.
