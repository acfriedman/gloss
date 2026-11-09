# GlossRead

Parses the sources once into declarations and their doc comments, so the lint and the model read the same thing. It knows Swift's syntax and doc format, and nothing of rules or contracts.

<!-- lyceum:video -->
[![Gloss Read: a narrated explainer](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-read/poster.jpg)](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-read/index.html)
<!-- /lyceum:video -->

## Overview

Every other module starts from a ``Reading``: each file's declarations, the modules it imports, and an index its links resolve against. Objective-C headers and module pages ride along, read for their type names and their prose. ``Revision`` reads the same sources at any commit or from git's index, so a diff compares like with like. It sits at the bottom of the package and depends only on swift-syntax.

## Topics

### Reading the sources

- ``Reading``
- ``DeclarationReader``
- ``SourceFiles``
- ``Revision``

### Declarations and their docs

- ``Declaration``
- ``DocComment``
- ``DocLine``
- ``DocStructure``
- ``Callout``
- ``Mention``

### Names and links

- ``SymbolIndex``
- ``ObjectiveCHeaders``
- ``ModulePage``

### Measuring

- ``Timing``
