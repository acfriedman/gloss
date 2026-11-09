---
title: "gloss: doc comments you can read as an interface"
status: draft 1
updated: 2026-11-09
pronounce: {}
sources:
  - README.md (the story told: what gloss is, its commands, rules, change stories and layers)
  - Package.swift (the modules and which depends on which)
  - Sources/GlossLint/Rules.swift (the house style's rules)
  - Sources/GlossModel/ChangeStory.swift (change stories and what coverage demands)
  - Sources/GlossModel/Contract.swift (a declaration's contract)
  - Sources/gloss/StoryCheck.swift (the gloss story command)
explains: "README.md"
verified: "dbfe30d4c812"
---

# Intent

- **Point:** gloss makes doc comments one checked shape, then reads the package through what those docs say: the same pass feeds a linter, a map, and a check that a branch explains itself.
- **For:** the project's audience: Swift developers who have not met gloss.
- **Angle:** start from the problem that doc comments drift and nobody reads them, then show each thing gloss builds on one parse, ending with the layers that keep it honest.
- **Length:** about three minutes, five scenes.
- **Notes:** the app cannot run in CI, so it is described from its README, never shown as screens. Rules and commands are quoted from the README and checked against the code.

## 01 · hook — Docs nobody trusts

> Visual: A Swift function `total()` with a doc comment of a few loose lines in the centre, one line struck through as wrong. Beside it, a faint question mark over the word "docs".

Doc comments are the one description of a Swift package that sits right beside the code. And most of the time, nobody reads them.

They drift. They have no shape, so each one is different. A tool can't rely on them.

gloss starts from a simple bet. If every doc comment has the same shape, the docs can be checked, and then they can be read as the interface they describe.

## 02 · shape — One shape for a comment

> Visual: A doc comment built line by line. A summary line labelled "what, then why". A blank line. Then callouts: Parameter, Returns, Throws, each lit as it is named. Code simplified.

The linter checks every triple-slash comment against one shape.

First, a summary of one or two sentences: what the declaration does, then why. Then a blank line. Then a markup block, with an entry for every parameter, the return value, and what it throws.

Each finding is one line in compiler format, so Xcode and GitHub Actions show it as it is. The exit status is one when any finding is an error, so the same command can gate continuous integration.

## 03 · one-pass — One parse, many uses

> Visual: A single box "swift-syntax parse" on the left. Arrows fan out to: lint findings, contracts, dependency graph. Then from those, five outputs listed on the right: interface export, map, why one type depends on another, what changed, change story check.

gloss parses every file once, with swift-syntax.

From that one pass, it builds each declaration's contract, and a dependency graph of types.

From those come an interface export, as JSON or a web page. A map of the package: its modules, folders, and types, and what each uses. The reason one type depends on another, in the words of the docs gloss already requires. What changed against a base revision, read straight from git, and what that change reaches.

## 04 · story — A branch explains itself

> Visual: A markdown file `.gloss/changes/<branch>.md` with a headline, a theme linking `Cart/total()` and `TaxTable`, and a note under `Cart`. Then a terminal line: `gloss story` failing with a changed type left out. Simplified from the README example.

A branch can explain itself. It keeps a change story in a file under dot gloss, changes, named for the branch.

A story has a headline, themes, and notes. Themes link the types they are about. A note tells the change from one type's side.

Then gloss story checks it. It fails while a type whose interface changed has no theme, or no note, or while a link names nothing. A change can't land unexplained.

## 05 · layers — Layers that keep it honest

> Visual: Six boxes stacked: Gloss Read at the bottom, then Gloss Lint and Gloss Model side by side, Gloss Map above, then Gloss Page and Gloss App. Arrows only point downward. A cross between Lint and Model.

The package is built in layers, and each depends only on the ones below it.

Gloss Read parses the sources. Gloss Lint holds the house style. Gloss Model holds what the docs say. Gloss Map arranges the model for reading. Gloss Page draws it as a web page, and Gloss App draws it in a macOS window.

Gloss Lint and Gloss Model never read from each other, so the model holds what the docs say whether or not the lint runs.

The page and the app draw from the same map, so they can't disagree. One shape for the docs, one pass over the code, and a package you read through its own words.
