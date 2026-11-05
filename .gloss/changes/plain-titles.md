# Set page titles upright

Page titles were set in italic serif, which Andrew asked to drop. They keep the serif and stand upright, in the app and on the HTML page alike.

## Titles stand upright

``HeadingView`` sets its title in the serif without italics, and the HTML page's title follows. Nothing else used italics, so ``View/textStyle(_:design:weight:monospacedDigit:)`` loses the option.

### ``HeadingView/body``

Sets the title upright, as asked.

### ``InterfacePage/style``

Drops the italic from the toolbar's title, so the page and the app match.

### ``TextSize``

Its doc links the text style modifier by its new name.

### ``ScaledTextStyle/italic``

Gone, since no title or text is set in italics now.

### ``ScaledTextStyle/body(content:)``

No longer slants the font, with nothing left to ask for it.

### ``View/textStyle(_:design:weight:italic:monospacedDigit:)``

Replaced by the same modifier without the italic option, which only page titles used.

### ``View/textStyle(_:design:weight:monospacedDigit:)``

The text style modifier as it stands, a size and a look with no slant.
