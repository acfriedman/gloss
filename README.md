# gloss

A doc-comment linter for Swift, and a macOS app for reading a package through the interface those docs
describe.

## How it works

gloss parses every file once with swift-syntax. The linter checks each `///` comment against one shape: a
one- or two-sentence summary (what, then why), a blank line, then a markup block for every parameter, the
return value, and what it throws. From the same pass, gloss builds each declaration's contract and a
dependency graph of types, and from those:
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
swift run -c release gloss path/to/YourPackage/Sources        # lint
swift run -c release GlossApp --root path/to/YourPackage      # read it
```

Each finding is one line in compiler format, so Xcode and GitHub Actions show it as is, and the exit status
is 1 when any is an error, so the same command gates CI. Build for release: a debug build is several times
slower on a large codebase.

## Commands

| Command | Does |
| --- | --- |
| `gloss <paths>` | lints; `--include-tests` reads `*Tests` folders too, `--summary` prints only counts by rule, `--style <file>` reads a house style other than the nearest |
| `gloss interface <paths>` | exports the interface: `--json <file>`, `--html <file>`, `--title <name>`, `--style <file>` |
| `gloss story [--base main] <paths>` | prints what the branch's story covers; fails while a changed type is left out |
| `gloss bench [--base <rev>] <paths>` | runs the app's work without a window and times each phase |

## The app

- **Opens like Xcode:** a welcome window of recent folders, then a blank page. ⌘⇧O is Open Quickly, ⌘T and
  ⌘W open and close tabs, ⌘← and ⌘→ go back and forward, ⌘R reads the sources again.
- **Three panes:** the list, an outline of modules, folders, and types; the details of what's selected; and
  the map.
- **The map** reads at levels: every type, the modules, one module, one folder. Focus on a type to see what
  uses it above and what it depends on below. A `+4` pill expands just that box. Pinch or scroll to zoom,
  drag to pan.
- **Changes** compares with a base: where the branch left `main` by default, another branch, or any
  base and head. New types are marked `+`, changed ones `~`, and the page opens on the branch's story.
- **Summary** sums up the interface's size, documentation, and findings, module by module.

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

## Rules

| Code | Fires when |
| --- | --- |
| `missing-doc` | a non-private declaration has no `///` comment; the house style can ask only from `public` |
| `block-doc` | the comment is `/** */` |
| `summary-empty`, `summary-sentences`, `summary-terminator`, `summary-capital`, `summary-opener` | the summary is missing, isn't one or two sentences, has no period, starts lowercase, or opens with "This method…" |
| `markup-order`, `markup-spacing`, `markup-case`, `markup-unknown` | a callout follows prose, touches the summary, is lowercase, or is a near miss like `- Return:` |
| `parameter-missing`, `parameter-unknown`, `parameter-empty`, `parameter-form`, `parameter-order`, `parameter-duplicate` | a parameter entry is missing, extra, empty, mixes forms, is out of order, or repeats |
| `returns-*`, `throws-*` | `- Returns:` or `- Throws:` is missing, unexpected, or empty |
| `symbol-link` | a single-backticked `Type.member` should be a ``` ``Type/member`` ``` link |
| `dead-link` | a ``` ``Symbol`` ``` link names nothing the sources declare |
| `exempt-reason`, `exempt-documented` | a `// gloss:exempt` marker has no reason, or sits beside a doc |

Types, properties, and enum cases get only the summary rules. Code fences in a comment are quoted, not
checked.

## Exemptions

A protocol requirement inherits the protocol's doc, so gloss skips:
- **known requirements** by signature, such as `hash(into:)`, `init(from:)`, `body`, and `description`;
- **members of a conformance extension** (`extension T: P`), for `missing-doc` only;
- **memberwise initializers**, whose body only assigns their parameters;
- **anything marked** `// gloss:exempt <reason>` on the line above.

## House style

The rules above are gloss's own house style. A project picks its own in `.gloss/style.json`, which gloss
reads from the current directory or the nearest folder above it, and the app from the folder it opens.
Every key is optional:

```json
{
  "severity": "warning",
  "rules": { "missing-doc": "error", "summary-*": "off" },
  "exclude": ["Sources/Generated", "**/*.pb.swift"],
  "requireDocs": "public"
}
```

| Key | Does |
| --- | --- |
| `severity` | the level of every rule `rules` doesn't name: `error` (the default), `warning`, or `off` |
| `rules` | a level per rule code, or per prefix ending in `*`; a code wins over a prefix |
| `exclude` | paths not linted, from the folder holding `.gloss`: `*`, `**`, `?`, or a folder for all of it; their declarations still resolve links |
| `requireDocs` | the narrowest access that owes a doc for `missing-doc`: `public`, `package`, or `internal` (the default) |

Warnings print as `warning:` and leave the exit status 0, so a team can bring a rule in before it gates
anything. A key or rule code gloss doesn't know stops the run, so a typo can't leave a rule on unnoticed.

## Environment

| Variable | Does |
| --- | --- |
| `GLOSS_TIMING=1` | prints every timed phase to standard error; they're also in Instruments and `log stream --predicate 'subsystem == "gloss"'` |
| `GLOSS_SNAPSHOT=<file.png>` | writes the app's window to a PNG once the sources are read, then quits |
| `GLOSS_SELECT` | selects first, comma-separated: `overview`, `summary`, `changes`, `module:Name`, or a type's id |
| `GLOSS_COMPARE` | compares with `<base>` or `<base>..<head>` first |
| `GLOSS_ZOOM`, `GLOSS_PREVIEW` | zooms in that many steps; previews a type's id as if hovered |

## The package

| Target | Holds |
| --- | --- |
| `GlossRead` | one pass over the sources: declarations, doc comments, links, and git revisions |
| `GlossLint` | the house style: the rules, their findings, and which declarations owe a doc |
| `GlossModel` | what the docs say: contracts, their graph, diffs, and stories |
| `GlossMap` | the model arranged for reading (`Atlas`), with the lint's findings beside it |
| `GlossPage` | the HTML page |
| `GlossApp` | the macOS app |

Each depends only on the ones above it. `GlossLint` and `GlossModel` both read from `GlossRead` and never
from each other, so the model holds what the docs say whether or not the lint runs. The page and the app
draw from the same `Atlas`, so they can't disagree.

## License

Copyright 2026 Andrew C. Friedman. Licensed under the [Apache License, Version 2.0](LICENSE).
