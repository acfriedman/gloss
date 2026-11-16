---
title: "gloss: doc comments you can read as an interface"
status: draft 2
updated: 2026-11-16
pronounce: {}
sources:
  - README.md (the story told: what gloss is, SwiftLucid, its commands, change stories and layers)
  - Package.swift (the modules, the SwiftLucid dependency, and which depends on which)
  - Sources/GlossModel/ChangeStory.swift (change stories and what coverage demands)
  - Sources/GlossModel/Contract.swift (a declaration's contract)
  - Sources/gloss/StoryCheck.swift (the gloss story command)
explains: "README.md"
verified: "a79b8bfe8c50"
---

# Intent

- **Point:** gloss reads the package through what its doc comments say. The linter that keeps those docs in one shape is SwiftLucid, its own project; gloss builds a map, a reading of each change, and a check that a branch explains itself on the same reading.
- **For:** the project's audience: Swift developers who have not met gloss.
- **Angle:** start from the problem that doc comments drift and nobody reads them, then show what gloss builds from one reading of the sources, ending with the layers that keep it honest.
- **Length:** about three minutes, five scenes.
- **Notes:** the app cannot run in CI, so it is described from its README, never shown as screens. The lint's rules now live in SwiftLucid and are not repeated here.

## 01 · hook — Docs nobody trusts

> Visual: A Swift function `total()` with a doc comment of a few loose lines in the centre, one line struck through as wrong. Beside it, a faint question mark over the word "docs".

Doc comments are the one description of a Swift package that sits right beside the code. And most of the time, nobody reads them.

They drift. They have no shape, so each one is different. A tool can't rely on them.

gloss starts from a simple bet. If every doc comment has the same shape, the docs can be checked, and then they can be read as the interface they describe.

## 02 · shape — One shape for a comment

> Visual: A doc comment built line by line. A summary line labelled "what, then why". A blank line. Then callouts: Parameter, Returns, Throws, each lit as it is named. Under it, a pill "SwiftLucid checks this" and the file name `.swiftlucid.json`. Code simplified.

The checking is done by Swift Lucid, the linter gloss builds on. It is its own project now.

It checks every triple-slash comment against the house style a project sets in a file named dot swiftlucid dot json.

gloss's own docs keep one shape. A summary of one or two sentences: what, then why. A blank line. Then a markup block, with an entry for every parameter, the return value, and what it throws.

gloss shows those findings beside each declaration.

## 03 · one-pass — One reading, many uses

> Visual: A single box "Swift Lucid reading" on the left. Arrows lead to: declaration contracts, dependency graph. Then from those, four outputs listed on the right: interface export, map, why one type depends on another, what changed; then a line "and what the change reaches".

gloss reads every file once, through Swift Lucid, which parses it with swift-syntax.

From that one pass, it builds each declaration's contract, and a graph of the dependencies between types.

From those come an interface export, as JSON or a web page. A map of the package: its modules, folders, and types, and what each uses. The reason one type depends on another, in the words of the docs gloss already requires. What changed against a base revision, read straight from git, and what that change reaches.

## 04 · story — A branch explains itself

> Visual: A markdown file `.gloss/changes/<branch>.md` with a headline, a theme linking `Cart/total()` and `TaxTable`, and a note under `Cart`. Then a terminal line: `gloss story` failing with a changed type left out. Simplified from the README example.

A branch can explain itself. It keeps a change story in a file under dot gloss, changes, named for the branch.

A story has a headline, themes, and notes. Themes link the types they are about. A note tells the change from one type's side.

Then gloss story checks it. It fails while a type whose interface changed has no theme, or no note, or while a link names nothing. A change can't land unexplained.

## 05 · layers — Layers that keep it honest

> Visual: Six boxes stacked: LucidRead (from SwiftLucid) at the bottom, then LucidLint (from SwiftLucid) and GlossModel side by side, GlossMap above, then GlossPage and GlossApp. Arrows only point downward. A cross between LucidLint and GlossModel.

The package is built in layers, and each depends only on the ones below it.

Lucid Read, from Swift Lucid, reads the sources. Lucid Lint, also from Swift Lucid, holds the house style. Gloss Model holds what the docs say. Gloss Map arranges the model for reading. Gloss Page draws it as a web page, and Gloss App draws it in a macOS window.

Gloss Model never imports Lucid Lint, so the model holds what the docs say whether or not the lint runs.

The page and the app draw from the same map, so they can't disagree. One shape for the docs, one reading of the code, and a package you read through its own words.
