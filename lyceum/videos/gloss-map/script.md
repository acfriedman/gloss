---
title: "Gloss Map"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark gloss-map` records the commit they were checked at.
sources:
  - Sources/GlossMap/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/GlossMap/Atlas.swift (the reviewed contract, the groups, the shared arrangement)
  - Sources/GlossMap/MapScope.swift (the levels, the budget of thirty boxes, the figure)
  - Sources/GlossMap/GraphLayout.swift (the rows layout, the box flags)
  - Sources/GlossMap/Reach.swift (reach directions and depth)
  - Sources/GlossMap/ReachWhy.swift (why a change reaches a type)
  - Sources/GlossMap/Changes.swift (the change reason and the changes figure)
  - Sources/GlossMap/ChangedFindings.swift (findings that fall on a change)
  - Sources/GlossMap/Highlight.swift (code colored by kind)
# The one file this video explains: always watched, and `lyceum embed gloss-map` shows the video in it.
explains: "Sources/GlossMap/README.md"
verified: "c2effe0758ea"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order. The narration is the only text sent to TTS, so it is
written for the ear: no identifiers that read badly aloud, short sentences. The intent above the
first scene is never narrated.
-->

# Intent

- **Point:** Gloss Map is the one place that decides how the model is arranged for reading, so the app and the page, which both draw from it, never disagree.
- **For:** the project's audience; contributors will find the types the page names.
- **Angle:** start with the problem of two front ends, then the Atlas that joins the model and the lint, then the map levels and the layout, then what a change reaches.
- **Length:** about a minute and a half, four scenes.
- **Notes:** names and numbers come from the sources. Declarations are simplified.

## 01 · one-arrangement — Two front ends, one arrangement

> Visual: Two boxes side by side at the top, "the app" and "the page". Both have an arrow down to one box in the middle, "Gloss Map". When the narration says they never disagree, the two arrows light up together.

Gloss has two front ends. The app, and the page.

Both show the same code. If each one decided for itself which types lead a module, or what a map draws, they would drift apart.

So Gloss Map decides once. It arranges the model for reading, and both front ends draw from it.

## 02 · atlas — The Atlas

> Visual: Two cards on the left, "Contract" and "Assessment". Arrows from both into a node "Atlas" in the middle. Out of Atlas on the right, four small pills: "levels", "focus", "reaches", "why". Under the pills, the line "struct Reviewed { contract; assessment }" in mono, marked simplified.

The Atlas is where the model and the lint meet.

It takes each contract, which is a declaration as read, and pairs it with the lint's assessment of it. That pair is called a reviewed contract. The lint is optional. Without it, the contracts read the same, and there are simply no findings.

From there the Atlas answers what a view asks. The levels of the map. The focus. What a type reaches. And why one type uses another.

## 03 · maps — Levels and layout

> Visual: A row of three boxes labelled "All types", "Modules", "One module", with arrows stepping from left to right. Above them the number "30" labelled "mapBudget". Below, a grid of small boxes in rows, with the label "GraphLayout: rows, top to bottom", and one dashed box labelled "boundary".

A big codebase can't be drawn as one graph a reader can follow. So the map has levels.

It opens at the most detailed level that fits the budget, which is thirty boxes. Every type, if they fit. Otherwise each module as one box, and a reader steps into a module. A module too large for the budget is drawn as folders.

What a level leaves outside is drawn as boundary boxes a reader can step into.

Graph Layout places the boxes in rows, top to bottom. It runs once, in Swift, so the page draws fixed pictures and the app draws the same boxes. The same graph always gives the same drawing.

## 04 · change — What a change reaches

> Visual: A small graph of five nodes. One node is tinted gold and labelled "changed". Two nodes above it and one below are lit, with arrows to it. A card slides in beside the graph with two lines: "why it changed" and "why it relies on it". At the end a line of code underneath, "ChangedFindings", with a pill "only touched declarations".

For a change, Gloss Map finds what the change reaches. That is the blast radius, drawn from the types that changed, outward.

A reach can follow what a type depends on, what uses it, or both.

For each type reached, the map can say why. Why the thing it relies on changed, from the branch's story. And why it relies on that thing, from the docs.

Findings are judged the same way. Changed Findings keeps only the findings on declarations the change added or changed. Code nobody touched can't fail the change.

Gloss Map decides what to show. The app and the page just draw it.
