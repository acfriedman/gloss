---
title: "Gloss Read"
status: draft 1
updated: 2026-11-09
pronounce: {}
sources:
  - Sources/GlossRead/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/GlossRead/Reading.swift (the Reading: files, index, imports, headers, module pages)
  - Sources/GlossRead/Declaration.swift (what a declaration is, independent of syntax)
  - Sources/GlossRead/DeclarationReader.swift (Entry and Details: doc, access, header, mentions)
  - Sources/GlossRead/DocComment.swift (doc lines and their source line numbers)
  - Sources/GlossRead/DocStructure.swift (summary, callouts, notes)
  - Sources/GlossRead/Mentions.swift (mention roles)
  - Sources/GlossRead/SymbolIndex.swift (links resolved against every file)
  - Sources/GlossRead/ObjectiveCHeaders.swift (type names only)
  - Sources/GlossRead/ModulePage.swift (a README read as a page)
  - Sources/GlossRead/Revision.swift (sources at a git revision or from the index)
  - Package.swift (Gloss Read depends only on swift-syntax)
explains: "Sources/GlossRead/README.md"
verified: "c2effe0758ea"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order. The narration is the only text sent to TTS, so it is
written for the ear: no identifiers that read badly aloud, short sentences. The intent above the
first scene is never narrated.
-->

# Intent

- **Point:** Gloss Read is the bottom of gloss. It reads the sources once into declarations, doc comments and an index, and knows nothing of rules or contracts, so the lint and the model look at exactly the same thing.
- **Angle:** start from the problem of two modules reading the same code twice, then follow one pass: the declarations, the index, and the same reading taken from any git revision.
- **Length:** about a minute and a half, four scenes.
- **Notes:** names, fields and behaviour come from the sources. Code on screen is simplified where marked.

## 01 · once — One reading for everyone

> Visual: Three boxes in a row at the bottom: "Gloss Lint" and "Gloss Model" on top, "Gloss Read" beneath them, with arrows from both upper boxes down to it. A card on Gloss Read reads "Reading". The two upper boxes light up as the narration names them. A small caption under Gloss Read: "depends only on swift-syntax".

Two modules in gloss care about the same thing: what the doc comments say.

The lint checks them against a house style. The model reads them as contracts. If each one parsed the sources on its own, they could disagree.

So both start from one Reading, made by Gloss Read. It sits at the bottom of the package. It knows Swift's syntax and doc format, and nothing of rules or contracts. It depends only on the swift syntax library.

## 02 · declaration — What one declaration holds

> Visual: A code card shows a short simplified declaration with a doc comment: a summary line, a "- Parameter" line, a "- Returns" line, then a function signature mentioning a type. On the right, a record card titled "Entry" with three rows: "declaration", "doc", "details". Highlights tie the pieces: the doc lines to "doc", the signature to "declaration", and the type name to a list of pills in "details": "property", "parameter", "returns", "body".

A Reading is made of declarations. Each comes as an entry with three parts.

The first is the Declaration itself: its kind, its name, its parameters, and whether it returns anything. It is plain data, kept apart from the syntax tree, so a rule can be tested from a literal.

The second is the Doc Comment, line by line, each with its source line number. A Doc Structure then reads it as a summary, callouts, and notes.

The third is the details. The access level, the declaration as written, and the type names it mentions. Each mention says where it sits: in a property, a parameter, a return, a throws clause, an inheritance clause, or only in a body.

## 03 · index — Names and links

> Visual: Left, three file cards stacked: "Swift files", "Objective-C headers", "module pages". Arrows run to a central card "Symbol Index". On the right a doc line with a link in double backticks, "``Reading``", and a check mark appears beside it once the index is reached. The Objective-C card carries a small label "names only".

The Reading also holds an index of everything the sources declare. A link in one file is checked against all of them.

Objective-C headers ride along. They are not parsed. Only the type names they declare are read, so a link to one still resolves.

And a module's page, the page in the module's folder, is read as a page, with the same rules as a doc comment. The lint can check it, and the app can lead with it.

Reading spreads the Swift files over every core, then builds the index.

## 04 · revision — Any commit

> Visual: A horizontal row of three commit dots labelled "main", "HEAD" and "index". A file stack hangs under each. A label "git cat-file" sits on a thin line from the repository to the stacks, with the caption "no checkout". Two stacks are joined by a double arrow labelled "compare like with like".

Sometimes the question is about an older version. Revision reads the same sources at any commit, straight from git, without checking anything out.

It can also read from git's index: what the next commit will hold. So a pre-commit hook judges the commit, not the working tree.

Because both sides are read the same way, a diff compares like with like. One reading, from any moment, for every other module to build on.
