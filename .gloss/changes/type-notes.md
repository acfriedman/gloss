# Tell each changed type's side of the story

Commit messages spoke for whole commits, so a type's page carried other types' reasons. The story now holds a note per type, written from where that type stands, so a reader zoomed in on it reads its change in its own terms beside the theme it belongs to.

## Write a note for each type

A `###` heading that is one link opens a note in the theme above it, the change told from that type's or member's side, even where it repeats the theme: the two together triangulate it.

### ``ChangeStory``

Reads notes under each theme: a `###` heading that is one link opens one, and any other heading stays prose. A note's link counts toward its theme, and the draft stubs a note for each changed type under the first theme that names it.

### ``ChangeStory/Note``

New: the link the heading is and the paragraphs under it.

### ``StoryCoverage``

Resolves each note to the type or member it names, and lists the types whose interface changed with no note of their own, nor one on a type they are nested in. A story is complete only once every such type has one.

### ``StoryCoverage/NotePlace``

New: where a note is, its theme and its place within it, so a page can find it again.

### ``StoryCoverage/MemberLink``

Now made outside the core, so a member's row can look up its notes.

## Show the notes where a reader zooms in

A type's page shows each theme that explains it with the type's own note beneath, and a member's row its member's note; the Changes page counts each theme's notes and lists the types still without one.

### ``StoryThemesView``

Sets each theme's prose over the type's note, or a note on a type it is nested in.

### ``StoryNoteView``

New: one note, its link over its prose, set off by an accent bar.

### ``MemberNotesView``

New: the notes on one member, under its row on its type's page.

### ``StoryGapsView``

Lists the types with no note of their own beside those no theme explains.

### ``ChangePageView``

Drops the commit messages, which spoke for whole commits rather than for the type.

### ``WhyChangedView``

Gone: it listed the commits behind a type's changes, whose messages spoke for everything they touched.

### ``CommitMessageView``

Gone with it: one commit's message on a type's page.

### ``CommitTagsView``

Gone: the commits under each declaration's row, replaced by the member's note.

### ``DeclarationChangesView``

Puts a member's note under its row in place of its commits.

### ``ChangeCommits``

Stays, for the outline without a story and the draft, where a commit is shown whole.

## Hold a branch to it

### ``StoryCheck``

Prints the types with no note of their own, and fails until each has one.
