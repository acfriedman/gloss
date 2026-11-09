---
title: "Gloss Model"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark gloss-model` records the commit they were checked at.
sources:
  - Sources/GlossModel/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/GlossModel/Interface.swift (build, the contracts, the graph and the module pages)
  - Sources/GlossModel/Contract.swift (what one declaration promises; its fields)
  - Sources/GlossModel/Graph.swift (nodes, edges and their roles)
  - Sources/GlossModel/Reason.swift (why one type uses another, from the docs)
  - Sources/GlossModel/InterfaceDiff.swift (the kinds of change; matching by name, moves)
  - Sources/GlossModel/ChangeCommits.swift (the commits behind each change, by git blame)
  - Sources/GlossModel/ChangeStory.swift (the story file, and StoryCoverage)
  - Sources/GlossRead/Mentions.swift (the roles of a mention)
# The one file this video explains: always watched, and `lyceum embed gloss-model` shows the video in it.
explains: "Sources/GlossModel/README.md"
verified: "c2effe0758ea"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order. The narration is the only text sent to TTS, so it is
written for the ear: no identifiers that read badly aloud, short sentences. The intent above the
first scene is never narrated.
-->

# Intent

- **Point:** Gloss Model turns the doc comments of a codebase into data: a contract for each declaration, a graph of which type uses which, and a comparison of two versions that can be held against a written story of the change. It never judges whether the docs follow the house style.
- **For:** the project's audience; contributors will find the types the page names.
- **Angle:** start with one declaration and what its comment promises, widen to the graph, then compare two versions, and end on the story that must explain every change.
- **Length:** about a minute and a half, four scenes.
- **Notes:** type and field names, roles and change kinds come from the sources. The story example is the one in the doc comment of the story type.

## 01 · contract — What a declaration promises

> Visual: A code card shows a short simplified declaration with a doc comment: a summary line, a parameter entry and a returns entry above "func build(sources:) -> Interface". When the narration says contract, a record card slides in on the right with real field names listed: kind, name, access, declaration, parameters, returns, summary, mentions. The doc lines tint to match the fields they fill.

Gloss Model reads what the docs say as contracts.

For every declaration, the Interface builds a Contract. It holds the signature as written, and the doc comment read as a promise. The summary. Each parameter with its type and its entry. What it returns, what it throws, and any callouts.

It also lists the type names the declaration mentions. Those mentions are what the next piece uses.

## 02 · graph — Which type uses which

> Visual: Four nodes: "Interface", "Contract", "Graph", "Reason". Arrows appear between them as the narration names roles. Each arrow carries a small pill with its roles: "property", "parameter", "returns", "body". An arrow whose only pill is "body" is drawn dim and labelled "implementation". Beneath, a line of text: "Contract.reason(toward:) → Reason".

From those mentions, the Graph is drawn. A node is a type with its members. An edge says that one type mentions another, and its roles say where.

A type can appear in a property, in a parameter, in a return, in a throws clause, or in a conformance. An edge made only of body mentions is implementation, not interface.

And a Reason says why. It reads what the declaration wrote about the type it uses, in the entry for the parameter or in the summary, so the answer is the author's own.

## 03 · diff — Comparing two versions

> Visual: Two columns, "base" and "head", each with a small stack of declarations. One declaration is in a different place in the head and is joined to its twin by a line, with the label "moved within a file is no change". Then five pills appear one by one: "added", "removed", "changed", "implementation", "moved". A renamed type is shown as one pill "removed" and one pill "added".

An Interface Diff compares two interfaces.

Things are matched by name, never by place. Code that only moves inside a file, or between files, is no change.

Every difference is one of five kinds. Added. Removed. Changed, when the signature or the doc differs. Implementation, when only what the body does differs, which changes no one's view of the interface. And moved, when a type keeps its name and goes to another module.

A renamed type reads as one removed and one added.

## 04 · story — Why it changed

> Visual: A file card titled ".gloss/changes/<branch>.md" shows simplified lines: a heading line "# Say why each change was made", a theme line "## Read the why from commits", and a link "``ChangeCommits``". On the right, a list of changes from the diff; each gets a check mark as the narration says a link explains it. One change stays unchecked and turns red, labelled "no reason".

A diff says what changed. Change Commits says who changed it, by reading git blame, so each change can quote the commit messages that wrote its lines.

A Change Story says why, in the author's words. It lives in the repository, in a file named for the branch. A heading, a summary, and themes, with links to the types and members each theme is about.

Story Coverage then checks the story against the diff. Every type whose interface changed needs a theme. Every change needs a note of its own. And every link has to name something real.

So the reason for a change is written down, and checked.
