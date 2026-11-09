---
title: "Gloss Lint"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark gloss-lint` records the commit they were checked at.
sources:
  - Sources/GlossLint/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/GlossLint/Linter.swift (the entry points, the assessment, the module page checks)
  - Sources/GlossLint/Rules.swift (the checks on one declaration, the summary opener rule)
  - Sources/GlossLint/Diagnostic.swift (the rules, the severity, the compiler format line)
  - Sources/GlossLint/HouseStyle.swift (the style file, its levels and keys)
  - Tests/GlossTests/RulesTests.swift (the opener example)

# The one file this video explains.
explains: "Sources/GlossLint/README.md"
verified: "dc775d6cbf92"
---

<!--
Format: one `## NN · id — Title` per scene.
-->

# Intent

- **Point:** Gloss Lint checks doc comments and module pages against a project's house style, reports each fix in compiler format, and knows nothing of the contract model, so a team can lint without the app.
- **For:** the project's audience; contributors will find the types the page names.
- **Angle:** start with one bad comment and the line it earns, then the pieces that make that line, then the house style that tunes it, then the separation from the app.
- **Length:** about a minute and a half, four scenes.
- **Notes:** the example comment and the rule code come from the sources and tests. Message text is simplified.

## 01 · report — A fix in compiler format

> Visual: A code card shows two lines: "/// This method records it." above "func f() {}". After the first sentence, a line types out below it in mono: "file:1:1: error: Do not open with "This method"; name the behavior directly [summary-opener]". Pieces of the line are tinted when named: file, line and column, severity, message, rule code.

Gloss Lint checks doc comments and module pages against a project's house style.

Take a comment that begins with, this method records it. Gloss Lint reports it in the format a compiler uses. The file, the line, the column, the severity, then the fix, and the rule code in brackets.

Because it looks like compiler output, Xcode, continuous integration and a commit hook can all show it as it is.

## 02 · pieces — Linter, Rules and Diagnostic

> Visual: Three nodes in a row: "Linter", "Rules", "Diagnostic". An arrow from Linter to Rules labelled "each declaration", and from Rules to Diagnostic labelled "each finding". Under Rules a small list of three rule codes: "missing-doc", "summary-opener", "returns-missing".

The Linter is the entry point. It runs the Rules over every declaration it reads.

Each rule is a single teachable failure, with a code. A missing doc comment. A summary that opens with this method. A function that returns a value but has no returns entry.

Every finding becomes a Diagnostic, which knows its file, line, column, rule and message, and renders itself as one line.

## 03 · style — The house style

> Visual: A file card titled ".gloss/style.json" with the real keys listed: severity, rules, exclude, requireDocs. To its right three pills: "error", "warning", "off", tinted red, gold and dim. An arrow from the card to the Linter node.

Each project sets its own house style, in a file named style dot json inside its gloss folder.

A rule can be an error, a warning, or off. A prefix such as summary star sets a whole family at once. Some paths can be excluded, and the style says which declarations owe a doc comment.

With no file, every rule is an error, and every declaration but the private ones needs a doc comment. A key gloss doesn't know is an error, so a typo never leaves a rule quietly on.

## 04 · apart — Lint without the app

> Visual: Two boxes side by side, "Gloss Lint" on the left and "contract model" on the right, with a broken line between them. A third box, "Assessment", sits on the left box's edge with an arrow crossing the gap to a box "the app's views".

Nothing in Gloss Lint knows the contract model. So a team can lint without the app, and the app can read docs without the lint.

The one thing that crosses is the Assessment. It is what the views take from the linter.

That is all the module does. It checks the prose, and says so in a line any tool can read.
