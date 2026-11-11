# gloss

A macOS app for reading a Swift package through the interface its doc comments describe. The
doc-comment linter it builds on is its own project, [SwiftLucid](https://github.com/acfriedman/SwiftLucid).

<!-- lyceum:video -->
[![gloss: doc comments you can read as an interface: a narrated explainer](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss/poster.jpg)](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss/index.html)
<!-- /lyceum:video -->

## How it works

gloss reads every file once through SwiftLucid, which parses it with swift-syntax and lints each `///`
comment against the project's house style. From the same reading, gloss builds each declaration's
contract and a dependency graph of types, and from those:
- an interface export, as JSON or a self-contained HTML page;
- a map of the package: its modules, folders, and types, and what each uses and is used by;
- why one type depends on another, in the words of the docs gloss already requires;
- what changed against a base revision, read straight from git, and what the change reaches;
- a check that the branch's change story explains every type whose interface changed.

## Requirements

- **macOS 14+** and a **Swift 6** toolchain (Xcode 16 or later).
- **git**, for comparing with a base.

## Getting started

```bash
git clone https://github.com/acfriedman/gloss && cd gloss
swift build -c release
swift run -c release GlossApp --root path/to/YourPackage      # read it
```

A folder is walked for `.swift` files, and for `.h` files whose Objective-C types the docs may link,
skipping hidden folders and those dependency managers fill: `SourcePackages`, `DerivedData`, `Pods`, and
`Carthage`. Build for release: a debug build is several times slower on a large codebase. To lint, use
SwiftLucid's `swiftlucid` command.

## Commands

| Command | Does |
| --- | --- |
| `gloss interface <paths>` | exports the interface: `--json <file>`, `--html <file>`, `--title <name>`, `--style <file>` |
| `gloss story [--base main] <paths>` | prints what the branch's story covers; fails while a changed type is left out |
| `gloss bench [--base <rev>] <paths>` | runs the app's work without a window and times each phase |

Each reads `*Tests` folders too with `--include-tests`.

## The app

- **Opens like Xcode:** a welcome window of recent folders, then a blank page. ⌘⇧O is Open Quickly, ⌘T and
  ⌘W open and close tabs, ⌘← and ⌘→ go back and forward, ⌘R reads the sources again.
- **Three panes:** the list, an outline of modules, folders, and types; the details of what's selected; and
  the map.
- **The map** reads at levels: every type, the modules, one module, one folder. Focus on a type to see what
  uses it above and what it depends on below. A `+4` pill expands just that box. Pinch or turn the wheel
  to zoom, and drag with the right button held, or two fingers, to pan well past the figure's edges; the
  scope button centers it again.
- **Changes** compares with a base: where the branch left `main` by default, another branch, or any
  base and head. New types are marked `+`, changed ones `~`, and the page opens on the branch's story.
- **Summary** sums up the interface's size, documentation, and findings, module by module.
- **Text size:** ⌥⌘+ and ⌥⌘− make the details' text bigger and smaller, ⌥⌘0 resets it, and Settings (⌘,) has
  the same choice; the list and the map keep their sizes.

## Change stories

A branch explains itself in `.gloss/changes/<branch>.md`, committed with it. Themes link the types they're
about as DocC links, and a `###` note tells the change from one type's side:

```markdown
# Totals include tax

Carts showed totals before tax, so checkout disagreed with the receipt.

## Tax

``Cart/total()`` now adds tax from ``TaxTable``.

### ``Cart``

`total()` keeps its signature; only the amount changes.
```

The Changes page leads with it. `gloss story` fails while a type whose interface changed has no theme or
no note, or a link names nothing.

## The lint

gloss shows SwiftLucid's findings beside each declaration, at the levels the project's house style sets
in `.swiftlucid.json`, read from the folder the app opens or, for `gloss interface` and `gloss bench`, the
nearest above the current directory. The rules, exemptions, hook modes, and the house style's keys are in
[SwiftLucid's README](https://github.com/acfriedman/SwiftLucid#rules).

## Module pages

Each module under `Sources` keeps a `README.md` that says what it does and groups its types, short enough
to read at a glance, and SwiftLucid's lint keeps it in step with the code:

```markdown
# GlossModel

Reads what the docs say as contracts and a graph.

## Overview

Every view starts from an ``Interface``. (Five sentences at most.)

## Topics

### The model

- ``Interface``
- ``Contract``
```

The summary answers to the same rules as a doc's, a link must name something, and every public type
must be linked somewhere on the page. The app leads a module's page with it, its types grouped by Topics.
SwiftPM wants each target to leave the file out of the build: `exclude: ["README.md"]`.

## Environment

| Variable | Does |
| --- | --- |
| `SWIFTLUCID_TIMING=1` | prints every timed phase to standard error; they're also in Instruments and `log stream --predicate 'subsystem == "swiftlucid"'`, since the timing is SwiftLucid's |
| `GLOSS_SNAPSHOT=<file.png>` | writes the app's window to a PNG once the sources are read, then quits |
| `GLOSS_SELECT` | selects first, comma-separated: `overview`, `summary`, `changes`, `module:Name`, or a type's id |
| `GLOSS_COMPARE` | compares with `<base>` or `<base>..<head>` first |
| `GLOSS_ZOOM`, `GLOSS_PREVIEW` | zooms in that many steps; previews a type's id as if hovered |
| `GLOSS_TEXT_SIZE` | sets the details' text size for one run, such as `1.5`, without storing it |
| `GLOSS_SEARCH` | types a search into the list for one run, as a snapshot asks |

## The package

| Target | Holds |
| --- | --- |
| `GlossModel` | what the docs say: contracts, their graph, diffs, and stories |
| `GlossMap` | the model arranged for reading (`Atlas`), with the lint's findings beside it |
| `GlossPage` | the HTML page |
| `GlossApp` | the macOS app |

Each depends only on the ones above it, and all of them on SwiftLucid's `LucidRead`, the one reading of
the sources. `GlossModel` never imports `LucidLint`, so the model holds what the docs say whether or not
the lint runs. The page and the app
draw from the same `Atlas`, so they can't disagree.

## License

Copyright 2026 Andrew C. Friedman. Licensed under the [Apache License, Version 2.0](LICENSE).
