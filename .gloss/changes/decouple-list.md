# Let the list follow only what is done in it

Selecting a type on the map or in the details selected it in the list too, opening its folders and scrolling to it, so the list never stayed where the reader left it. The list now drives the editor, and the editor never moves the list.

## Give the list its own selection

``Workspace/listSelection`` is the row last clicked in the list, which the list shows selected; clicking a row still opens it. Nothing else sets it, and selecting elsewhere no longer opens the rows that hold a type or scrolls the list to it. ``ListPaneView`` reads its own selection, and ``RowHover`` lights a row only while the pointer is on it, not while the map previews its type.
