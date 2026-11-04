# Let the reader size the details' text

The details are where gloss is read, a type's contract, its notes, and why it is used, and their text was fixed at macOS's small sizes. macOS gives an app's text styles no Dynamic Type to follow, and setting a type size on the pane changes nothing, so the pane's text now scales itself.

## Text styles that follow a size

``TextSize`` keeps the scale, remembered between launches, and the steps from 85% to 200%. ``ScaledTextStyle`` turns a text style into a font at that scale: the style itself at 100%, so the default looks exactly as it did, and the style's own point size, read from AppKit, times the scale otherwise; ``ScaledPointSize`` does the same for a badge's fixed size. ``View`` gains the two modifiers that set them, and every font in the details now goes through one, so text that names no style of its own, such as a doc's notes, takes body text at the pane's size. ``EnvironmentValues`` carries the scale, 1 outside the details, so a view shared with the list, such as ``StatView``, keeps its size there.

### ``TextSize``

New: the scale's key, its steps, the next step up and down, and each text style's size in points.

### ``ScaledTextStyle``

New: a text style at the pane's scale, unchanged at 100%.

### ``ScaledPointSize``

New: a fixed point size at the pane's scale.

### ``View``

Gains ``View/textStyle(_:design:weight:italic:monospacedDigit:)`` and ``View/textSize(_:weight:design:)``.

### ``EnvironmentValues``

Gains the scale the details set their text at.

### ``StatView``

Sets its label and number through the modifiers, so the summary's numbers grow with the details while the list's stay put.

## The View menu and Settings choose it

``GlossApp`` adds Make Text Bigger, Make Text Smaller, and Make Text Normal Size to the View menu, on Option-Command as in Safari, since Command-plus and Command-minus already zoom the map, and a Settings window, ``SettingsView``, with the same choice and a line of a type's page to judge it by. ``EditorSplitView`` hands the scale to the details, or `GLOSS_TEXT_SIZE`'s for one run, so a snapshot can show a size without storing it.

### ``GlossApp``

Gains the three text size commands and the Settings scene.

### ``SettingsView``

New: the text size, chosen from the steps, over a sample of a type's page at that size.

### ``EditorSplitView``

Sets the details' scale from the stored size, or from `GLOSS_TEXT_SIZE` when a snapshot gives one.

## A view modifier's body is the protocol's to document

gloss's own lint asked for a doc on `body(content:)`, which `ViewModifier` requires and documents, so ``Declaration/knownRequirements`` now holds it, and `makeBody(configuration:)` for SwiftUI's style protocols.
