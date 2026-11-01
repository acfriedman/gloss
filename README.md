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
the access level and zoom in the toolbar (zoom is also ⌘= and ⌘-). The toolbar's arrows, or ⌘← and
⌘→, go back and forward through the places visited: each selection, level, and focus, with the
depth chosen there. ⌘1 hides the list, or shows it again. ⌘⇧O is Open Quickly, as in Xcode: type a few letters of a type's name, in order but not
necessarily together (`dpv` finds `DetailPaneView`), move with the arrow keys, and press Return to
open it in the map's focus, with only what uses it and what it uses. The list is an outline: each
module as its source folders hold it, at full depth, with nested types under the type that declares
them. Modules start open and folders and nested types closed, so a large module opens as its top
folders; searching or filtering opens whatever holds a match, and selecting a type from the map or a
chip opens the rows around it. In focus, a menu in the map header picks what to draw around the
type: Neighbors, what uses it above and what it depends on below; All below, everything it depends
on; or All above, everything that uses it. All three are one reach (`Atlas.reach`) with a depth
stepper. By default Neighbors draws depth 1 and the other two draw whole steps while they fit 30
boxes; a chosen depth stays when the mode changes, and a new type starts at the default. A reach
draws only the edges from one step to the next, marks types at the cut that lead further as dashed
boxes counting what lies beyond, and keeps the most connected when even the first step is over;
clicking a box re-roots it. A focus or reach that crosses modules draws them as lanes, the focused
type's module a little warmer, split into bands of rows where that saves width: each row starts as a
band of its own, and neighboring bands merge when a module continues across the rows where they meet
and the merged band is no wider than the widest. Within a band, modules whose rows never meet stack
in one column, so a module that runs through several rows keeps one container while its neighbors
change beside it, and one on both sides of the type gets a container on each, never one spanning a
row it has nothing on. The focused type anchors one vertical axis through every band: its module's lane is
in the middle of its band, and the other lanes go around it in organ-pipe order, the ones with the
most edges to it nearest, each on the side that keeps the figure narrowest. Each map opens centered
and shrunk to fit the pane, never past its natural size; a pinch or the magnifier in its corner
zooms, clicking the percentage fits it again, and a new level or focus fits again. Hovering a box on
the map or a row in the list previews it in the details pane over the selection, and lights it on
the map; moving into the pane keeps the preview to read, and moving away returns to the selection.
In a focus, the preview opens with why the box is there: each trail of drawn dependencies from it
back to the focused type, read top to bottom as the map draws them, in the words of the declarations
each runs through, every step open so the chain reads whole. A box reached from several types gets
a trail through each, up to three, and each trail climbs on by one way only. A type's page lists the same under Why for every
type beside it, one row per neighbor that unfolds to its reasons. Hovering a chip in the pane lights
its box. Declarations are colored as Xcode's default themes color
them, from swift-syntax's own classification (`Highlight` in `GlossMap`), with the types the scanned
sources declare told apart from the types they only use. It reads the folder's `Sources` directory
when it has one, ⌘R reads it again, and the next launch reopens the last folder. A member's file and
line open in Xcode. The folder takes a flag because AppKit reads a bare path argument as a document
to open and then opens no window.

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
mention but are not graph nodes. A parameter mention also records which parameters take the type,
so `Contract.reason(toward:)` can say why a declaration depends on a type from its own doc: the entry
for each parameter that takes it, the `- Returns:` or `- Throws:` entry, and the summary, which
answers for a property, a conformance, or a use inside a body. Since gloss requires those docs, the
reason is usually already written where the type is used.

The page is three panes on one screen: every type listed on the left, the text of one type in the
middle, and the dependency map on the right, where it takes whatever width the other two leave.
Nothing navigates away, so the map stays in view. A toolbar across the top holds what applies to
every pane: the access level, and the button that hides or shows the list, which stays in the same
place either way. Both dividers drag (or step with the arrow keys) to resize; sizes are kept in the
browser, and double-clicking a divider restores its default.

- **Overview** is what the details pane shows first: each module's entry points, meaning root types
  used from another module and root types nothing else in their module uses.
- **The map** shows root types, nested types folded in, with every dependency: signature ones solid,
  and ones used only inside bodies dashed. A figure of types from two or more modules draws each
  module as a lane: a soft container holding that module's boxes on every row, named at its top.
- **Module colors**: every module has its own color, from a hash of its name (`Atlas.colorSlots`),
  so it is the same on every run, in the page and in the app, and after unrelated edits; two
  modules that hash alike are told apart. The color tints the module's lanes and its module and
  folder boxes, and marks its name in the list. Types stay neutral. Layout happens in Swift, so it is plain SVG. It reads at
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
| `missing-doc` | A non-private, non-override function, initializer, subscript, macro, type (`typealias` and `associatedtype` included), property, or enum case has no `///` comment. Members of a `private` type or extension count as private; a `private(set)` setter does not make the property private. |
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
| `parameter-order` | The entries do not follow the signature's order. |
| `parameter-duplicate` | One parameter has more than one entry. |
| `returns-missing` / `returns-unexpected` / `returns-empty` | `- Returns:` absent on a value-returning function, present on a `Void` one, or empty. |
| `throws-missing` / `throws-unexpected` / `throws-empty` | `- Throws:` absent on a throwing function, present on a non-throwing one, or empty. |
| `dead-link` | A ``` ``Symbol`` ``` link names nothing the scanned sources declare. Links resolve from the documented declaration's scope outward, as DocC resolves them; a leading module name, a DocC disambiguation suffix (`-swift.property`, `-7tndx`), a member a conformance synthesizes (`allCases`), and anything under another module (`SymbolReference.externalPrefixes`) are accepted. This rule reads every file, so it runs on a whole project, not `Linter.check(source:file:)`. |
| `exempt-reason` | A `// gloss:exempt` marker with no reason after it. |
| `exempt-documented` | A declaration carries both a marker and a `///` doc. |

Types, properties, and enum cases get only the summary rules. Declarations inside function bodies
are skipped, and so are a script's top-level variables (in a file with top-level statements, such as
`main.swift`), which are the entry point's locals. Fenced code in a comment (```` ``` ````) is quoted,
not prose: no rule reads it, and the interface keeps it as one note with its line breaks. Sentence counting ignores code spans
(matched by backtick run length, so `` `` ```x`` `` `` is one span) and common abbreviations
(`e.g.`, `etc.`). A misplaced markup block is one `markup-order` finding; its entries still count
as documentation, so it does not also fan out into `parameter-missing`.

## Exemptions

A method that implements a protocol requirement inherits the protocol's contract, and a doc
comment on it would only restate that. Syntax cannot prove that a method is a requirement, so
the harness accepts four proxies:

1. **Known requirements**, matched by signature and skipped entirely: `init(from:)`,
   `encode(to:)`, `hash(into:)`, `init(rawValue:)`, the literal initializers, `makeIterator()`,
   `next()`, `main()`, `run()`, the swift-syntax macro `expansion(...)` roles, the result-builder
   `build...` methods, and the properties conformances require, such as `body`, `id`,
   `description`, `rawValue`, and `allCases`. The cases of a `CodingKeys` enum, which only name
   stored properties, count too. The list is `Declaration.knownRequirements`.
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
