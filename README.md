# gloss

A doc-comment harness for Swift. It parses each file with swift-syntax and reports, as errors, every
declaration whose `///` comment does not match the org's shape: a one-or-two-sentence summary
(what, then why), then a markup block that explains every parameter, the return value, and each
thrown error, then notes. The shape itself is specified in `.claude/skills/doc-comments/SKILL.md`.

## Usage

```bash
swift run -c release gloss ../haruspec/Sources
```

Paths may be files or directories. Directories are walked for `.swift` files, skipping `.build`
and any directory whose name ends in `Tests` unless `--include-tests` is passed. `--summary` prints only the per-rule
counts. Exit status is 1 when anything was reported, so the same command gates CI and hooks.

Each finding is one line in compiler format, so Xcode and GitHub Actions render it unchanged:

```
Sources/Spec/Intent.swift:82:1: error: `declares` returns a value but has no `- Returns:` entry; ... [returns-missing]
```

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
   // gloss:exempt implements Tracer.record, documented on the protocol
   func record(_ event: Event) {}
   ```

   The marker and a `///` doc on the same declaration is an error; keep one.
4. **Memberwise initializers**, whose body is nothing but `self.x = x` for their own parameters,
   are exempt from `missing-doc` and the parameter rules: an entry there could only restate the
   property's doc. A summary they do carry is still shape-checked. Any other statement, default
   value, or expression in the body makes it a real initializer with a contract of its own.
