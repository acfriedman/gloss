---
title: "The gloss command"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark sources-gloss` records the commit they were checked at.
sources:
  - Sources/gloss/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/gloss/main.swift (the four commands, their options and exit statuses)
  - Sources/gloss/ChangeLint.swift (staged and since: only the declarations a change touched)
  - Sources/gloss/Export.swift (the interface JSON, schema 2)
  - Sources/gloss/StoryCheck.swift (gloss story and its exit statuses)
  - Sources/gloss/Bench.swift (the timed phases and the table)
# The one file this video explains: always watched, and `lyceum embed sources-gloss` shows the video in it.
explains: "Sources/gloss/README.md"
verified: "c2effe0758ea"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order.
-->

# Intent

- **Point:** the gloss command is the front door to everything else. One program with four jobs: lint, export the interface, check a branch's story, and time the app's work. Its output is plain enough for Xcode, a build server, or a commit hook to use as is.
- **Angle:** start with the one line a developer types, then walk the four jobs, ending on how exit statuses let other tools trust it.
- **Length:** about a minute and a half, four scenes.
- **Notes:** everything comes from Sources/gloss. Code on screen is simplified where marked.

## 01 · lint — The lint, and only what changed

> Visual: A terminal card in the middle. A command line "gloss Sources" types in. Below it three diagnostic lines appear, in compiler format (simplified): "Foo.swift:12:5: error: ..." in red and one in gold for a warning. A tag "Xcode" and a tag "commit hook" sit to the right with arrows from the output. Then the command changes to "gloss --since main Sources" and the diagnostics shrink to one line, with a caption "only what the change touched".

The gloss command is the way in to everything else. Point it at a folder, and it lints.

It reads the whole of each path, and reports every finding. Each one prints in the format a compiler uses. So Xcode shows it inline, a build server can read it, and a commit hook can stop on it.

Two options narrow the lint to a change. Staged judges the next commit. Since takes a revision, and judges your branch against it.

Either way, the whole change is read, so links into untouched files still resolve. But only findings on declarations the change added or changed are reported.

## 02 · interface — The interface as data

> Visual: A code card with the command "gloss interface --json out.json Sources". Arrow to a document card "JSON" with rows "schema", "files", "contracts", "assessments", "graph". The "assessments" row is tied to "contracts" by a bracket labelled "same index". A second, smaller output card "web page" with the option "--html".

The second job is to export the interface.

Give it a folder and the interface command writes JSON. With no file named, it goes to standard output. Or you can ask for a web page instead.

The JSON holds the files read, one contract for every declaration, and the graph of how they mention each other. Beside the contracts sit the lint's assessments, one for each, at the same index.

The reading is done once, and the contracts and the lint meet only here. The shape carries a schema number, now two, so other tools know when it changes.

## 03 · story — The story check

> Visual: A branch label "feature/search" with an arrow to a file card ".gloss/changes/feature-search.md" (simplified name). Beside it a list of changed types, each with a check or a cross. Two output lines appear in mono: "not in the story: ..." and "no note of its own: ...". At the end three exit statuses: 0 "complete", 1 "gaps or none", 2 "git cannot say".

The third job is the story check. Every branch is meant to explain why it changed things, in a story file named for the branch.

The story command finds where the branch left its base, and compares the interface then with the interface now. Every type that changed must appear in the story, with a note of its own.

It prints what is missing. Types not in the story. Types with no note. Links that name nothing.

The exit status says the rest. Zero for a complete story. One for gaps, or no story at all. Two when git cannot answer.

## 04 · bench — Timing, and the exit statuses

> Visual: A table card titled "gloss bench" with columns "phase", "runs", "total ms", "max ms" and three rows: "read files", "trails", "highlight members" (illustrative values omitted: show dashes). A caption "the app's work, without the app". Then a row of status chips along the bottom: "0 clean", "1 errors", "64 usage", "65 style file broken", "66 no such path".

The last job is the bench. It does the work the app does for a package, and times each phase.

It reads the files, builds the map, narrows the list as you type, lays out every level, and works on the pages of the busiest types. Then it prints a table. For each phase, how many times it ran, how long it took in all, and its slowest run. A slow phase shows at a glance, and a change that slows one shows against an earlier run.

The command also keeps its promises to other tools. The lint exits with one only when there are errors, so a style can bring a rule in as a warning first. A missing value gives usage status. A broken style file stops the run. And a path that does not exist is an error, so a typo cannot pass as a clean run.
