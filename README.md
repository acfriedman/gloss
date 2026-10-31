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

## Interface

```bash
swift run -c release gloss interface Sources --html interface.html --json interface.json
```

`gloss interface` reads the same sources and exports each declaration's contract: its signature
without the body, effective access level, enclosing type, parameter types, return type, throws
clause, and the doc comment read as summary, parameter entries, returns, throws, callouts, and notes,
plus any findings. `--json` writes it as data (`schema` marks the shape's version); `--html` writes
a self-contained page. With neither flag, JSON goes to standard output. `--title` names the page;
it defaults to the current directory's name.

Each declaration also records the type names it mentions and where: an inheritance clause, a
property, a parameter, the return type, a typed `throws`, or a body. Names are resolved the way
Swift looks them up (innermost enclosing type first, then outward, then other scanned modules) into
a dependency graph of types. A module's top-level statements count as one `top-level code` entry, so
an executable's entry point appears in the graph. Names no scanned source declares are kept on the
mention but are not graph nodes.

The page is three panes on one screen: every type listed on the left, the dependency map in the
middle, and the text of one type on the right. Nothing navigates away, so the map stays in view.
The list collapses, and both dividers drag (or step with the arrow keys) to resize; sizes are kept
in the browser, and double-clicking a divider restores its default.

- **Start here** is what the right pane shows first: each module's front door, meaning root types
  used from another module and root types nothing else in their module uses.
- **The map** shows root types, nested types folded in, with signature dependencies by default and
  body-only dependencies behind a toggle. Layout happens in Swift, so it is plain SVG. It reads at
  levels: all types, all modules, one module, and one folder. It opens on all types when they fit
  30 boxes, and otherwise on the module overview. A module over 30 types that spans several
  folders is drawn as its folders, each a level of its own. A level draws what lies outside it as
  dashed boxes that step into their own level, and one still over 30 draws its most connected
  boxes and lists the rest. Selecting a module or folder moves the map to it; selecting a type keeps
  the current level when it draws that type, and otherwise moves to the widest level that does.
- **Hovering** a box on the map or a name in the list previews that type in the right pane and lights
  it and its neighbors on the map; moving away returns to the selection, and moving into the pane
  keeps the preview while you read. **Selecting** keeps it, and updates the address so back,
  forward, and refresh work. Hovering a type chip in the pane lights that type on the map.
- **A type** reads top to bottom: what uses it, the type, what it conforms to, holds, takes,
  returns, and throws through its signatures, the types it nests, and, folded, what its bodies use.
- **A member** is one line (`(source: String) → [Diagnostic]` plus the first sentence of its
  summary) that opens to its full contract and the types it uses. Overrides start folded, and
  members with findings start open.

Access filtering defaults to public when the sources declare anything public, and to internal
otherwise.

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
