# Let a change's reason read first, the rest folded until asked

On a type's Changes page, the story's reason for each change was crowded by docs, dependency lists, and the map's lists of what it leaves undrawn. Now a changed member shows its signature and the story's note, and its doc, the changed dependencies, and the undrawn lists wait folded until opened.

## A member's doc folds into its row

``MemberRowView`` can keep its doc folded until the row opens, and the Changes page asks it to. A doc that changed shows its before and after inside the fold too.

### ``MemberRowView/showsBrief``

Added so the Changes page can fold a member's doc away, while a type's own page still shows it at a glance.

### ``MemberRowView/docChange``

Added so a changed doc's before and after sit with the doc they belong to, behind the same click.

### ``MemberRowView/body``

Shows the first sentence only when asked, and the doc's before and after when the row opens. What unfolds now spans the row, so a short unfolding, such as an exemption alone, starts at the same edge as a long one instead of drifting right.

### ``DeclarationChangesView/body``

Folds each changed member's doc into its row, so the story's note is the first prose under the signature.

## Lists of what else changed start folded

A changed type's dependencies that changed, and the map's lists of what it leaves undrawn, now start folded to their headings. Either choice holds across tabs, levels, and folders for as long as gloss runs.

### ``Workspace/foldsUnderMap``

Starts folded now, so the map has the pane to itself until the reader asks for what it left out.

### ``Workspace/foldsChangedDependencies``

Added so the dependencies that changed wait under their heading, as the map's lists do.

### ``FoldEyebrowView/text``

The heading, shown with its count so a folded list still says how much it holds.

### ``FoldEyebrowView/isFolded``

Bound to the workspace, so the choice holds as the reader moves between pages.

### ``FoldEyebrowView/body``

Turns its chevron as the map's fold does, so every fold in gloss reads the same.

### ``ChangePageView/workspace``

Read for the fold's choice, which lives in the workspace.

### ``ChangePageView/body``

Shows the dependencies that changed only when their heading is open.
