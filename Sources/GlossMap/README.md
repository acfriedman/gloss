# GlossMap

Arranges the model for reading: which types a module leads with, what each map level draws, and how it is laid out. The app and the page both draw from it, so they never disagree.

## Overview

``Atlas`` joins each contract with the lint's assessment and answers what a view asks: levels, focus, reaches, and why one type uses another. ``GraphLayout`` lays a ``MapFigure`` out in rows, and ``Highlight`` colors code as the pages show it. For a change, it finds what the change reaches, as ``ChangeReason`` and ``ReachWhy``, and which findings fall on it, as ``ChangedFindings``.

## Topics

### The arrangement

- ``Atlas``
- ``InterfaceSummary``
- ``OutlineItem``
- ``ListFilter``
- ``ListOutline``
- ``QuickOpenMatch``
- ``Wording``

### Maps

- ``MapScope``
- ``MapFigure``
- ``GraphLayout``
- ``Reach``
- ``ReachDirection``
- ``ModulePalette``
- ``Highlight``

### Changes

- ``ChangeReason``
- ``ChangesFigure``
- ``ReachWhy``
- ``ChangedFindings``
