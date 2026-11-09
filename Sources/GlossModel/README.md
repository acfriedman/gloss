# GlossModel

Reads what the docs say as contracts, and the types as a graph of which uses which. It holds what the docs say, never whether they follow the house style.

<!-- lyceum:video -->
[![Gloss Model: a narrated explainer](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-model/poster.jpg)](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-model/index.html)
<!-- /lyceum:video -->

## Overview

``Interface`` builds a ``Contract`` for every declaration and the ``Graph`` between types. ``InterfaceDiff`` compares two interfaces, moves included, and ``StoryCoverage`` checks that a branch's ``ChangeStory`` gives every change a reason. ``Reason`` and ``ChangeCommits`` say why, from the docs and from the commits.

## Topics

### The interface

- ``Interface``
- ``Contract``
- ``Graph``
- ``Reason``

### Changes

- ``InterfaceDiff``
- ``ChangeCommits``

### Stories

- ``ChangeStory``
- ``StoryCoverage``
