# Open what the list's search finds, quickly at any size

Since modules started closed, a search found its matches inside closed modules, so the list looked empty. Now a search or the findings filter opens every module and row that holds a match, leaves the rest out, and works the list out once per change, at most 300 matches drawn.

## A search opens what it finds

While the list narrows, each module that holds a match shows open and the others are left out. A line above the modules says how many match, and when there are more than the list draws.

### ``ListPaneView/body``

Draws each module as a plain open section while filtering, since flipping a section's expansion as its rows change made the outline view reenter itself.

### ``ListPaneView/rows(of:atlas:)``

Shared by the open section and the collapsible one, so both draw the same rows.

### ``ListPaneView/header(of:)``

Shared the same way, so a module's header reads alike whether or not the list is filtering.

### ``Workspace/isFiltering``

Asks the filter itself whether it narrows, so the list and the workspace never disagree.

### ``Workspace/expansion(ofModule:)``

Reads only the reader's choice again, since a filtering list draws modules open without it.

## The list is worked out once per filter

``ListFilter`` says what narrows the list, and ``Atlas/listOutline(_:)`` works out every module's rows for it at once. The workspace keeps the result until the filter or the folder changes, so a hover never works it out again.

### ``ListFilter/query``

Trimmed and lowercased once, so matching never does it again.

### ``ListFilter/findingsOnly``

Part of the filter, so changing it works the list out afresh.

### ``ListFilter/minimumRank``

Part of the filter for the same reason.

### ``ListFilter/limit``

Three hundred matches, about as many rows as the list draws at once without a stall.

### ``ListFilter/init(search:findingsOnly:minimumRank:)``

Makes the filter from what the reader typed and chose, cleaned once.

### ``ListFilter/isNarrowing``

Says whether the list should open what matches and leave out the rest.

### ``ListOutline/modules``

Only the modules holding a match while narrowing, so an empty module does not crowd the results.

### ``ListOutline/matches``

Counted past the limit, so the list can say how many more there are.

### ``ListOutline/shown``

How many the rows hold, for the line that says the list stopped short.

### ``ListOutline/empty``

The list before a folder is read.

### ``ListOutline/Module/name``

The module the rows belong to.

### ``ListOutline/Module/rows``

The module's rows for the filter.

### ``ListOutline/Module/id``

Lets the list tell the modules apart by name.

### ``Atlas/listOutline(_:)``

Finds the matches in one pass over the types, then builds only the modules that hold one. On swift-syntax it takes 5 ms or less in a release build.

### ``Atlas/nodesByModule``

Lets an outline read its own module's types without scanning every type, once per module.

### ``Atlas/searchNames``

Lowercases every type's and member's name once, at load, instead of at every keystroke.

### ``Atlas/init(_:assessments:)``

Builds both of those as it arranges the interface.

### ``Atlas/outline(of:showing:)``

Reads its module's types from the table instead of filtering every type.

### ``Workspace/listCache``

Keeps the list for its filter, so a redraw reads it rather than working it out.

### ``Workspace/listOutline``

Replaces a per-module outline worked out on every redraw with the whole list, worked out once per filter.

### ``Workspace/outline(of:)``

Gone, replaced by the list worked out once.

### ``Workspace/atlas``

Clears the kept list when a new folder is read.

### ``Workspace/snapshotIfAsked()``

Types `GLOSS_SEARCH` into the list, so a snapshot can show a search.

### ``Bench/run(sources:style:base:in:includeTests:)``

Times the list for a few searches, so a slow one shows up in the bench.
