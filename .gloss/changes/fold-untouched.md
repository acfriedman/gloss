# Fold what the map leaves undrawn

The lists under the map, of what it leaves undrawn, can run long on the Changes level, where the untouched types around the changes number in the dozens. They now fold to one line that counts them, and stay folded for as long as the app runs. Folding them showed a type listed twice, which is fixed too.

## Fold the lists to one line

### ``UnderMapFoldView``

New: the line over the lists, "Not drawn" with what each list holds counted, and a chevron that folds them or opens them again.

### ``Workspace``

Keeps whether the lists are folded, for as long as the app runs, across tabs, levels, and folders; a new launch starts with them open.

## List each change once

### ``Atlas/changesFigure(_:minimumRank:budget:includeUntouched:)``

A changed type left out to fit the budget could be counted again as a neighbor of a drawn one, and listed twice. A change is never a neighbor now, whether it is drawn or not.
