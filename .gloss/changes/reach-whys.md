# Say why each reach matters, a sentence at a time

A reach row said what reached a type but never why, so a reader asked "it uses that, but why?" of every row. Now each row answers twice, a sentence or two each, and every change in a story carries its own reason beside it.

## Two short answers for each reach

``ReachWhy`` answers why the thing a type relies on changed, and why the type relies on it. Both answers come from text already written: the story, the commits, and the docs at each use.

### ``ReachWhy/changed``

Holds the first answer apart, so a row can say plainly when nothing written says why.

### ``ReachWhy/user``

Kept because the changed type is sometimes the one that relies on the reached type, which turns the question around.

### ``ReachWhy/uses``

One answer per declaration that relies on the change, because each may rely on it for its own reason.

### ``ReachWhy/answer(_:from:)``

Builds every answer the same way, so no lead runs past two sentences.

### ``ReachWhy/Answer/lead``

The part a reader sees first, short enough to take in at a glance.

### ``ReachWhy/Answer/source``

Says where the words came from, so a reader can tell the story's reasons from a commit's or a doc's.

### ``ReachWhy/Answer/more``

Keeps the rest of what was written, for a reader who opens the row.

### ``ReachWhy/Use/name``

Names the relying declaration, since a type can rely on one change in several places.

### ``ReachWhy/Use/answer``

Optional, so a declaration whose doc is silent shows as a gap rather than as nothing.

### ``Atlas/why(_:reaching:in:story:coverage:commits:)``

Added so a reach row can say why without the view knowing where stories and docs keep their words. It looks to the member's note first, then the type's, the theme's, and the commit's.

### ``Sentences/split(_:after:)``

Added so every lead stops at two sentences. It ends a sentence only where ``Sentences/count(in:)`` would, never inside code or after "e.g.".

## Each reach row unfolds a level at a time

``ReachRowView`` leads with what reached the type, then its two whys. Everything else waits under More.

### ``ReachedView/workspace``

Read because the story, its coverage, and the commits live in the workspace.

### ``ReachedView/id``

Added because a row's whys are asked from the reached type's side.

### ``ReachedView/diff``

Added so a reach without a note can fall back to the commit behind its change.

### ``ReachedView/body``

Hands each reach to a row instead of drawing it inline, so each row can fold on its own.

### ``ReachRowView/reason``

The reach the row answers for.

### ``ReachRowView/atlas``

Needed to name the types a row links.

### ``ReachRowView/why``

Worked out once by the caller, so the row only draws it.

### ``ReachRowView/isOpen``

Each row folds on its own, so opening one leaves the rest at a glance.

### ``ReachRowView/body``

Puts the two whys right under what reached the type, the order a reader asks them in.

### ``ReachRowView/what``

Keeps the one line a row always shows apart from the rest.

### ``ReachRowView/declaration``

The declaration behind a reach, whose before and after now wait in the fold.

### ``ReachRowView/hasMore``

Hides More when nothing is folded, so a row never offers an empty fold.

### ``ReachRowView/more``

Moves was and now out of every row's first glance, behind the whys a reader asks first.

### ``WhyLineView/title``

Says which question the line answers, why it changed or why it is relied on.

### ``WhyLineView/answer``

The lead to show, absent when nothing was written.

### ``WhyLineView/missing``

A quiet line for a silent story or doc, so the gap shows instead of hiding.

### ``WhyLineView/body``

Sets a lead in the story's own prose, its links as code.

### ``WhyMoreView/answer``

The answer whose rest unfolds.

### ``WhyMoreView/body``

Names where an answer was written above what follows its lead, so a reader can go read the rest at its source.

### ``ChangePageView/body``

Gives the reach rows the reached type and the change, which they now answer from.

## Reasons sit beside their changes

A note now shows beside the change it is about, a member's under its row and a type's under its own change. The story box on a type's page keeps only each theme's blurb.

### ``StoryThemesView``

Its doc says it shows each theme's blurb only, since every change's reason now sits beside the change.

### ``StoryThemesView/body``

No longer sets the type's note inside the story box, where it repeated what each row now says.

### ``StoryThemesView/notes(in:coverage:)``

Gone with the notes the story box no longer shows.

### ``TypeNotesView/workspace``

Read because the story and its coverage live in the workspace.

### ``TypeNotesView/node``

The type whose own change the notes explain.

### ``TypeNotesView/body``

Shows a type's own note only where its change is shown: under its move, or under its changed declaration.

### ``NotesBoxView/story``

The story the notes come from.

### ``NotesBoxView/places``

Which of its notes to show.

### ``NotesBoxView/body``

One quiet box for every note set beside a change, a type's or a member's.

### ``MemberNotesView/body``

Draws its notes in the shared box, so a member's reason and a type's look alike.

### ``StoryNoteView/showsLink``

Added so a note beside its change skips the heading the row already gives.

### ``StoryNoteView/body``

Leaves out the link when asked, since a long signature wrapped over two lines under its own row.

### ``DeclarationChangesView/body``

Sets a type's own note under its move or its changed declaration, where the reason belongs.

## Every change needs a reason

A story is complete only once every change has a note beside it, a member's body and a gone member included. A new type is told by its theme and its members' notes, so it needs no blurb of its own.

### ``StoryCoverage``

Its doc gives the rule: every declaration that differs needs a reason, and a type needs its own only when it is gone, moved, or declared differently.

### ``StoryCoverage/withoutNotes``

Now lists only the types whose own change no member row carries, since a type's members say the rest.

### ``StoryCoverage/membersWithoutNotes``

Added so `gloss story` and the Changes page can name each change still owed a reason.

### ``StoryCoverage/typeKeywords``

Tells a type's own declaration from its members', so each change is owed the right note.

### ``StoryCoverage/typesOwingNotes(_:)``

Added so the check and the draft agree on which types owe a note of their own.

### ``StoryCoverage/membersOwingNotes(_:)``

Added so the check and the draft agree on which members owe one: every one that differs, private or not.

### ``StoryCoverage/isComplete``

A story is complete only once every change has its reason.

### ``StoryCoverage/init(story:diff:head:base:)``

Resolves a member's link only to a type that declares it, so a mistyped note is caught rather than shown under no row.

### ``ChangeStory/draft(for:commits:)``

Writes a note for every change, so a fresh draft already passes. A type changed only in its bodies is drafted too, and file scope's declarations by name.

### ``StoryCheck/run(sources:base:in:includeTests:)``

Prints each change still owed a reason as a link ready to paste.

### ``StoryGapsView/body``

Lists the changes still owed a reason on the Changes page, beside the types that are.
