# gloss

A doc-comment harness for Swift. It parses each file with swift-syntax and reports, as errors, every
declaration whose `///` comment does not match one consistent shape: a one-or-two-sentence summary
(what, then why), a blank line, then a markup block that explains every parameter, the return
value, and each thrown error, then notes. The rules below define that shape.

## Installation

Add gloss as a SwiftPM dependency, or clone it and build the executable:

```bash
swift build -c release
```

## Usage

```bash
swift run -c release gloss path/to/YourPackage/Sources
```

Paths may be files or directories. Directories are walked for `.swift` files, skipping `.build`
and any directory whose name ends in `Tests` unless `--include-tests` is passed. `--summary` prints only the per-rule
counts. Exit status is 1 when anything was reported, so the same command gates CI and hooks.

Each finding is one line in compiler format, so Xcode and GitHub Actions render it unchanged:

```
Sources/App/Cart.swift:82:1: error: `total` returns a value but has no `- Returns:` entry; ... [returns-missing]
```

## Design

The package is four layers, each a target that depends only on the ones before it, so the compiler
keeps them apart:

| Target | Holds |
|---|---|
| `GlossCore` | Reading, the contract model and its graph, and the lint. |
| `GlossMap` | The model arranged for reading (`Atlas`): entry points, map levels, the focus, and their layout. |
| `GlossPage` | The HTML page, rendered from that arrangement. |
| `GlossApp` | The macOS app, drawn from the same arrangement. |

One pass reads the source; two consumers use what it reads and never meet each other.
`DeclarationReader` walks each file once and produces, per declaration, what the rules need, its doc
comment, and the details the interface model needs. `Linter` runs `Rules` over those to produce
diagnostics, and `Contract` and `Graph` build the model from them. `Interface` sets contracts and
assessments side by side, and `Atlas` joins them only to arrange them for a reader. Every decision
about what to show is made there, so the page and the app cannot disagree.

## App

```bash
swift run GlossApp --root path/to/YourPackage
```

The same three panes as the page, in a native window: the list, one type's text, and the map, with
the access level and zoom in the toolbar (zoom is also ⌘= and ⌘-). ⌘1 hides the list, or shows it
again. The list is an outline: each module as its source folders hold it, at full depth, with nested
types under the type that declares them. Modules start open and folders and nested types closed, so
a large module opens as its top folders; searching or filtering opens whatever holds a match, and
selecting a type from the map or a chip opens the rows around it. Each map opens centered and shrunk
to fit the pane, never past its natural size; a pinch or the magnifier in its corner zooms, clicking
the percentage fits it again, and a new level or focus fits again. Hovering a box on the map or a
row in the list previews it in the details pane over the selection, and lights it on the map; moving
into the pane keeps the preview to read, and moving away returns to the selection. Hovering a chip
in the pane lights its box. Declarations are colored as Xcode's default themes color them, from
swift-syntax's own classification (`Highlight` in `GlossMap`), with the types the scanned sources
declare told apart from the types they only use. It reads the folder's `Sources` directory when it
has one, ⌘R reads it again, and the next launch reopens the last folder. A member's file and line
open in Xcode. The folder takes a flag because AppKit reads a bare path argument as a document to
open and then opens no window.

For reviews from a script, `GLOSS_SNAPSHOT=out.png` writes the window to a PNG once the sources are
read and quits; `GLOSS_SELECT` selects a node id (or `module:Name`) first, `GLOSS_ZOOM` zooms in
that many times, and `GLOSS_PREVIEW` previews a node id as if hovered.

## Interface

```bash
swift run -c release gloss interface Sources --html interface.html --json interface.json
```

`gloss interface` reads the same sources and exports each declaration's contract: its signature
without the body, effective access level, enclosing type, parameter types, return type, throws
clause, and the doc comment read as summary, parameter entries, returns, throws, callouts, and notes.
Beside each contract, at the same index in `assessments`, is what the linter concluded about it:
whether a doc is required, why the declaration is exempt if it is, and its findings. `--json` writes it as data (`schema` marks the shape's version); `--html` writes
a self-contained page. With neither flag, JSON goes to standard output. `--title` names the page;
it defaults to the current directory's name.

Each declaration also records the type names it mentions and where: an inheritance clause, a
property, a parameter, the return type, a typed `throws`, or a body. Names are resolved the way
Swift looks them up (innermost enclosing type first, then outward, then other scanned modules) into
a dependency graph of types. A module's top-level statements count as one `top-level code` entry, so
an executable's entry point appears in the graph. Names no scanned source declares are kept on the
mention but are not graph nodes.

The page is three panes on one screen: every type listed on the left, the text of one type in the
middle, and the dependency map on the right, where it takes whatever width the other two leave.
Nothing navigates away, so the map stays in view. A toolbar across the top holds what applies to
every pane: the access level, and the button that hides or shows the list, which stays in the same
place either way. Both dividers drag (or step with the arrow keys) to resize; sizes are kept in the
browser, and double-clicking a divider restores its default.

- **Overview** is what the details pane shows first: each module's entry points, meaning root types
  used from another module and root types nothing else in their module uses.
- **The map** shows root types, nested types folded in, with every dependency: signature ones solid,
  and ones used only inside bodies dashed. Layout happens in Swift, so it is plain SVG. It reads at
  levels: all types, all modules, one module, and one folder. It opens on all types when they fit
  30 boxes, and otherwise on the module overview. A module over 30 types that spans several
  folders is drawn as its folders, each a level of its own. A level draws what lies outside it as
  dashed boxes that step into their own level, and one still over 30 draws its most connected
  boxes and lists the rest. Selecting a module or folder moves the map to it; selecting a type keeps
  the current level when it draws that type, and otherwise moves to the widest level that does.
- **Zoom** buttons (and the `+` and `-` keys) step between levels: in from the module overview to a
  module, a folder, and last to **focus**, which isolates the selected type with only what uses it
  (above) and what it depends on (below), at most 24 of each. Selecting a neighbor while focused
  re-centers on it, so a reader can walk the graph one type at a time; zooming out climbs back.
- **Hovering** a box on the map or a name in the list previews that type in the details pane and lights
  it and its neighbors on the map; moving away returns to the selection, and moving into the pane
  keeps the preview while you read. **Selecting** keeps it, and updates the address so back,
  forward, and refresh work. Hovering a type chip in the pane lights that type on the map.
- **A type** reads top to bottom: what uses it, the type, what it conforms to, holds, takes,
  returns, and throws through its signatures, the types it nests, and what its bodies use.
- **A member** is one line (`(source: String) → [Diagnostic]` plus the first sentence of its
  summary) that opens to its full contract and the types it uses. Overrides start folded. Members
  with findings start open when the whole interface has 100 findings or fewer, and more than two
  findings on one declaration fold behind their count.

Type views are built in the page from compact JSON that gloss embeds, so a large codebase's page
stays small (swift-syntax, at 19,000 declarations, is about 13 MB). gloss decides everything the
views show; the page's script only fills templates from that data.

Access filtering defaults to internal, in the page and the app alike, so every module's own types
show, including an app's, whose types are never public.

The page loads nothing and stamps no time, so it works offline as a CI artifact and the same
sources always render the same bytes. It shows only what the JSON holds. The command always exits 0;
the lint command is the gate.

## Rules

| Code | Fires when |
|---|---|
| `missing-doc` | A non-private, non-override function, initializer, subscript, macro, or type has no `///` comment. Members of a `private` type or extension count as private. |
| `block-doc` | The comment is `/** */`. |
| `summary-empty` | The comment opens with a blank `///` or a callout. |
| `summary-sentences` | The summary has zero or more than two sentences. |
| `summary-terminator` | The summary does not end with a period. |
| `summary-capital` | The summary starts with a lowercase letter. |
| `summary-opener` | The summary opens with `This method…`, `This class…`, and the like. |
| `markup-order` | A callout appears after prose; the markup block must follow the summary directly. |
| `markup-spacing` | The first callout sits on the line right after the summary; one blank `///` line separates them. |
| `symbol-link` | A single-backticked `name(label:)` or `Type.member` names a symbol; DocC links only ``` ``name(label:)`` ``` / ``` ``Type/member`` ```. Paths under Foundation-style types (`SymbolReference.externalPrefixes`) are left alone. |
| `markup-case` | A callout keyword is not capitalized (`- returns:`). |
| `markup-unknown` | A near-miss keyword (`- Return:`, `- Param:`). |
| `parameter-missing` | A parameter has no `- Parameter x:` or nested `  - x:` entry. |
| `parameter-unknown` | An entry names something that is not a parameter. |
| `parameter-empty` | An entry has no description. |
| `parameter-form` | `- Parameters:` and `- Parameter x:` are mixed on one declaration. |
| `returns-missing` / `returns-unexpected` / `returns-empty` | `- Returns:` absent on a value-returning function, present on a `Void` one, or empty. |
| `throws-missing` / `throws-unexpected` / `throws-empty` | `- Throws:` absent on a throwing function, present on a non-throwing one, or empty. |
| `exempt-reason` | A `// gloss:exempt` marker with no reason after it. |
| `exempt-documented` | A declaration carries both a marker and a `///` doc. |

Properties and enum cases are not required to carry a doc, but once they do, the summary rules
apply. Declarations inside function bodies are skipped. Sentence counting ignores code spans
(matched by backtick run length, so `` `` ```x`` `` `` is one span) and common abbreviations
(`e.g.`, `etc.`). A misplaced markup block is one `markup-order` finding; its entries still count
as documentation, so it does not also fan out into `parameter-missing`.

## Exemptions

A method that implements a protocol requirement inherits the protocol's contract, and a doc
comment on it would only restate that. Syntax cannot prove that a method is a requirement, so
the harness accepts three proxies:

1. **Known requirements**, matched by signature and skipped entirely: `init(from:)`,
   `encode(to:)`, `hash(into:)`, `init(rawValue:)`, the literal initializers, `makeIterator()`,
   `next()`, `main()`, `run()`, the swift-syntax macro `expansion(...)` roles, and the result-builder
   `build...` methods. The list is `Declaration.knownRequirements`.
2. **Members of a conformance extension** (`extension T: P { … }`) are exempt from `missing-doc`.
   A doc they do carry is still shape-checked. This is a proxy with a known leak: an undocumented
   helper placed in such an extension is not reported.
3. **An explicit marker** on the line above the declaration, reason required:

   ```swift
   // gloss:exempt implements Store.save, documented on the protocol
   func save(_ item: Item) {}
   ```

   The marker and a `///` doc on the same declaration is an error; keep one.
4. **Memberwise initializers**, whose body is nothing but `self.x = x` for their own parameters,
   are exempt from `missing-doc` and the parameter rules: an entry there could only restate the
   property's doc. A summary they do carry is still shape-checked. Any other statement, default
   value, or expression in the body makes it a real initializer with a contract of its own.

## License

MIT. See [LICENSE](LICENSE).
