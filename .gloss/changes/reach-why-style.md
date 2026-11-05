# Set a reach's reason as the story's notes are set

A reach row set its "why it changed" as plain text, while every other reason for a change sits in the story's blue box. Now the reason reads as a note does, the doc's answer reads as doc text, and a dropped dependency no longer asks why it is relied on.

## A reason looks like a reason everywhere

The why from the story or a commit sits in the same box as a member's note, and the why from the code's doc stays plain and quieter. A dependency that is gone shows only why it went.

### ``ReachRowView``

Its doc says the two whys now look like what they are: a reason for a change, and a doc's answer.

### ``ReachRowView/body``

Sets the reason in the story's box and the doc's answer quieter, and asks a dropped dependency nothing about relying on it.

### ``ReachRowView/isDropped``

Added because a dependency that is gone is relied on no more, so that question does not apply.

### ``ReachRowView/hasMore``

Leaves a dropped dependency's doc answers out of what folds, as it leaves them out of the row.

### ``ReachRowView/more``

Unfolds no doc answers for a dropped dependency, and words a silent doc plainly.

### ``WhyLineView``

Its doc says it is a doc's answer now, set quieter as doc text is.

### ``WhyLineView/body``

Sets the answer in the quieter color the details give doc text.

### ``StoryReasonView/text``

The reason to set, as the story or a commit writes it.

### ``StoryReasonView/body``

Draws the story note's bar and box, so a reach's reason and a member's note look alike.

## A dropped dependency says why it went

A dependency that went is explained by the note on the declaration that dropped it.

### ``Atlas/why(_:reaching:in:story:coverage:commits:)``

Looks first at the notes on the declarations a dependency runs through, so a dropped one is explained by the note on what dropped it. It falls back to the type's note and the theme as before.
