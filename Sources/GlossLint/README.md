# GlossLint

Checks doc comments and module pages against a project's house style. It reports each fix in compiler format, so Xcode, CI, and a commit hook show it as is.

<!-- lyceum:video -->
[![Gloss Lint: a narrated explainer](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-lint/poster.jpg)](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-lint/index.html)
<!-- /lyceum:video -->

## Overview

``Linter`` runs ``Rules`` over a reading and reports each ``Diagnostic`` at the level the project's ``HouseStyle`` sets. Nothing here knows the contract model, so a team can lint without the app, and the app can read docs without the lint. ``Assessment`` is the one thing the views take from it.

## Topics

### Linting

- ``Linter``
- ``Rules``
- ``Rule``
- ``Diagnostic``
- ``Assessment``

### The house style

- ``HouseStyle``

### Reading prose

- ``Sentences``
- ``SymbolReference``
