# Give the summary a page of its own

The summary sat under the list as four numbers. It is now a row below Overview that opens a page with all of it, and the list keeps only the filter it uses.

## Sum the interface up in the model

``InterfaceSummary`` holds the interface's size and health, overall and by module: declarations, public declarations, types, documentation, and findings, with the findings by rule, the declarations by access, and the types with the most findings. ``Atlas/interfaceSummary()`` takes it from the atlas's groups, so the page shows only what the model counts.

## Open it from the list

``Workspace/Selection`` gains a summary, drawn at the map's default level, which ``ListPaneView`` lists under Overview and ``DetailPageView`` opens on ``SummaryPageView``. Each module is two lines there, its name with its findings over its counts, through ``ModuleNameView``, so a long name fits the details pane. ``ListFilterView`` keeps the findings filter under the list, in place of ``SummaryView``, which is gone, and ``StatView`` sets each number. ``Workspace`` treats the summary as it does the overview.
