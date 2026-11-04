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
swift run -c release GlossApp --root path/to/YourPackage
```

Build it for release on a large codebase: a debug build parses several times slower and draws pages
more slowly too.

Without `--root` it opens on a welcome window, as Xcode does: Open Folder… (⌘O) on the left, or a
folder or `Package.swift` dropped anywhere on it, and the folders opened most recently on the right,
newest first and chosen, so Return or a double click opens it; each row's menu shows it in Finder or
takes it off the list. File › Open Recent lists the same folders, and ⌘⇧1 brings the welcome window
back. Turn off "Show this window when gloss opens" and a launch reopens the last folder instead.

A folder opens on a blank page, as Xcode opens with no editor: no tabs, and Open Quickly (⌘⇧O) to
find a type, or a row in the list. ⌘W closes the current tab, the last one returning to the blank
page, and on the blank page closes the window, which quits.

The same three panes as the page, in a native window: the list, one type's text, and the map, with
the access level and zoom in the toolbar (zoom is also ⌘= and ⌘-). The toolbar's arrows, or ⌘← and
⌘→, go back and forward through the places visited: each selection, level, and focus, with the
depth chosen there. The details and the map sit under a bar of tabs, as Xcode's editor does, beside
the one list: each tab keeps its own place, focus mode, depth, and Back and Forward. ⌘T opens a tab
where you are, ⌘W closes it (the last one leaves the blank page), ⌘⇧[ and ⌘⇧] move between tabs, and
⌘-click on a list row, box, or chip, Open in New Tab from its menu, or ⌥⏎ in Open Quickly opens
it in a new tab. Tabs are named for what they show, marked with its module's color, and dragged
to reorder; the line between the details and the map drags too, and keeps its place. ⌘1 hides the list, or shows it again. ⌘⇧O is Open Quickly, as in Xcode: type a few letters of a type's name, in order but not
necessarily together (`dpv` finds `DetailPaneView`), move with the arrow keys, and press Return to
open it in the map's focus, with only what uses it and what it uses. The list is an outline: each
module as its source folders hold it, at full depth, with nested types under the type that declares
them. Modules, folders, and nested types all start closed, so the list opens as one row per module,
and closing a row closes everything under it, so opening it again shows only what it holds directly;
searching or filtering opens whatever holds a match, and selecting a type from the map or a chip opens
the rows around it. In focus, a menu in the map header picks what to draw around the
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
In a focus, the preview is a page of its own about the box's tie to the focused type: its
declaration and doc, then each trail of drawn dependencies from it back to the focused type, read
top to bottom as the map draws them, in the words of the declarations each runs through, every step
open so the chain reads whole, and the map lights the same trails. Clicking a box in a focus pins
that page, under a bar that closes it, or Esc, back to the focused type's page, with the map keeping
the trail lit; the pin is a place Back returns from, and Keep on a preview pins it too. Double-clicking
a box focuses on it; outside a focus, a click selects a type and a double click focuses on it. A
single click acts at once, never waiting to see whether a second follows. A box reached from several types gets
a trail through each, up to three, and each trail climbs on by one way only. A type's page lists the same under Why for every
type beside it, one row per neighbor that unfolds to its reasons. Hovering a chip in the pane lights
its box. Declarations are colored as Xcode's default themes color
them, from swift-syntax's own classification (`Highlight` in `GlossMap`), with the types the scanned
sources declare told apart from the types they only use. It reads the folder's `Sources` directory
when it has one, and ⌘R reads it again. A member's file and
line open in Xcode. The folder takes a flag because AppKit reads a bare path argument as a document
to open and then opens no window.

For reviews from a script, `GLOSS_SNAPSHOT=out.png` writes the window to a PNG once the sources are
read and quits, on the blank page unless something is selected; `GLOSS_SELECT` selects a node id (or `module:Name`) first, `GLOSS_ZOOM` zooms in
that many times, and `GLOSS_PREVIEW` previews a node id as if hovered. `GLOSS_SELECT` takes several,
joined by commas, such as `changes,GlossMap/Atlas`, and `GLOSS_COMPARE` compares with a base first,
`develop`, or a base and head, `develop..feature`. Without `--root`, the snapshot is of the welcome
window.

## Performance

The work that grows with the codebase stays off the main thread: reading and parsing, which spreads
files over every core; comparing with a base; drawing each map level, laid out in the background
while the map keeps the drawing before; and working out every declaration's colors once after a read,
so pages draw from a cache. Pages build only the rows on screen, a Why row reads its reasons only
when it opens, and a row of chips shows the first 40 with the rest behind a button.

Every phase is timed with `Timing` (`GlossCore`): an interval under Points of Interest in
Instruments, a debug line in the unified log, and with `GLOSS_TIMING=1` a line on standard error.
The calls that can be slow time themselves, from their first line (`Timing.begin` and `Timing.end`):
reading files and revisions, building, arranging, and comparing an interface, each level's figure
and layout, reaches, outlines, Open Quickly, and a Why row's or a neighbor's reasons. Whatever calls
them is timed without saying so, and views never mention `Timing`; the calls cheap enough to make
thousands of times a frame, such as a label or a rank, are not measured.
The app also logs `select`, `preview`, and `open folder` as they happen, and `main thread blocked`
whenever the main thread answers more than 50 ms late, whatever held it, so a choppy moment shows
beside what caused it:

```bash
log stream --level debug --predicate 'subsystem == "gloss"'
```

`gloss bench` runs the app's work without a window and prints a table of each phase: runs, total,
and the slowest run with what it worked on. It reads and builds the interface, draws every map
level, lists every module, runs Open Quickly, and for the 20 most connected types draws their
reaches and works out their pages; `--base <revision>` adds the comparison, its figure, and its
marks. Run it before and after a change to see a regression:

```bash
swift run -c release gloss bench Sources
swift run -c release gloss bench --base main Sources
```

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
reason is usually already written where the type is used. Where it is not, as for a view's `body` or
a private property, which owe no doc, the docs of what the declaration uses are forwarded and marked
as such: the summaries of the members its body reaches, on the type named outright (`Atlas.make()`)
or through a variable whose declared type is known (`workspace.select(…)`, from a parameter or a
property of the same type), matched by name; else the used type's own summary. Reaching a type
through such a variable also counts as using it inside a body.

An interface can be compared with a base (`InterfaceDiff`): the types, declarations, and dependencies
added, removed, or changed, matched by name rather than place, so code that only moves is no change.
A changed declaration says whether its signature or its doc changed, and a changed dependency gives
its roles before and after, so a type that was only used inside bodies and is now taken or returned
reads as entering the interface. `Revision` reads the base straight from git, at any revision, without
checking it out, choosing files as the working tree's are chosen.

The app marks what changed on the map. The toolbar's Changes menu picks the base: where the branch
left `main` (or `master`), which a pull request compares against and the app picks by default, where
it left another branch here (the eight committed to most recently are listed, so `develop` is there
under git flow), the last commit, or nothing. Compare… takes any base and head: a branch, a remote's
branch, a tag, or a commit, typed or picked, the base from where the head left it or as it is, and
the head the working tree unless one is named; a named head is read from git (`Revision.sources`),
the whole window shows it, its subtitle says which, and its source links, which would open the files
on disk, are off. The base picked is kept for the folder. The base is read once per commit and
compared again on every reload. A new
type's box gets a green `+` badge and a box holding a change, its nested types', or for a module or
folder any of its types', an amber `~`; in a focus, new and changed dependencies are drawn green and
amber. A type whose declarations are written and documented as before but whose bodies differ is an
implementation change, marked with a quieter gray `~`: each declaration's body, accessors, and
initial value are fingerprinted from their tokens (`Contract.bodyFingerprint`), so reformatting and
comments are no change. A line under the map counts what is new, changed, changed only inside, and
gone across the interface and names the gone types, which the map cannot draw yet.

With a comparison on, the list opens with Changes, a level of its own (`Atlas.changesFigure`): the
changed types and the neighbors a change reaches, those touching the most changes first, with only
the dependencies that have a change at an end, since those are the ones a change can break. A
neighbor is reached when its dependency with a changed type is itself new or changed, or when it uses
a changed type and either the type's declaration changed or it reaches a member whose signature
changed or that is gone; an added member breaks no one, and a change to docs alone reaches no one. A
dependency dropped since the base reaches the type it was on too, and is drawn as a red dashed line
between the two; a type changed only inside its bodies reaches no one by that alone, and comes after
the interface changes when they are over the budget.
Members are matched by name as bodies reach them, so the untouched neighbors are counted and listed
under the map rather than dropped, and the Untouched checkbox draws them too. When the
changes alone are over 30 boxes, the most connected are drawn and the rest are listed. Its page lists
the changes module by module, each changed type with its declarations that changed and whether the
signature, the doc, or the body did, the gone types struck through, the dependencies of types that
were already there that entered or left the interface, and the dependencies dropped from bodies. A click selects a type and keeps the level; a
double click focuses on it, and zooming out of that focus returns to Changes.

On this level a type's page, hovered or selected, shows only what the change means for it. A changed
type's page lists its declarations that changed, each unfolding to its contract, with what the base
wrote beside a changed signature (`was`, carried by `InterfaceDiff`), the gone ones struck through,
its nested types that changed, and its dependencies that changed: what it depends on, and the types
already there that depend on it.
A new type's page lists what it declares. A neighbor's page says how the changes reach it
(`Atlas.changeReasons`): a dependency that is new or changed, a changed declaration of the type it
uses, or a member it uses whose signature changed or that is gone, naming its declarations that use
it, with the signature before and now. An untouched neighbor's page says that no change reaches it.
The bar over a selected type's page trades it for the whole page and back.

The Changes page leads with why. A branch's story, `.gloss/changes/<branch>.md` at the repository's
top (`ChangeStory`), is a `#` headline, a summary, and `##` themes, each prose that links the types
and members it is about as DocC links between double backticks, such as ``` ``Cart/total()`` ```. The
page opens on the headline and summary, then each theme with the changed types it explains, which
light together on the map while the pointer is on the theme; each type's page opens on the themes
that explain it. `StoryCoverage` resolves the links against both sides of the diff: a link to a type
explains it and its nested types, a member link names the member, and a link may start with its
module. Types whose interface changed that no theme links are listed as not in the story, and links
that name nothing are listed too; a type changed only inside its bodies needs no theme. Without a
story, the page lists the commits as its outline, each with the types it changed, and Draft the Story
from the Commits writes a first draft, a theme per commit, and opens it. The story is committed with
the branch, so it is reviewed with the change and stays as its record; `pr:` in its front matter names
the pull request once there is one. `gloss story --base main Sources` prints what the branch's story
covers and fails while a type it should explain has no theme, for CI.

Each changed type's page says why in its authors' words (`ChangeCommits`, in `GlossCore`): the
messages of the commits that made its changes, oldest first, each subject over its body's first
paragraph, unfolding to the rest. Every changed declaration lists its own commits by short hash and
subject, and its doc's summary before and now when the doc changed. A declaration is matched to
commits by its lines alone, its doc comment included: `git blame` over the range names the commit in
it that last wrote each line, and for a declaration that is gone, `git blame --reverse` names the last
commit that had it, after which the next one deleted it. Lines not committed yet say so instead. A
commit's message speaks for everything it changed, so one large commit explains each declaration it
touched in the same words.

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

Copyright 2026 Andrew C. Friedman. Licensed under the [Apache License, Version 2.0](LICENSE).
