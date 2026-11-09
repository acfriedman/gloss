---
title: "Gloss Page"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark gloss-page` records the commit they were checked at.
sources:
  - Sources/GlossPage/README.md (the page told: the summary, the Overview and the Topics)
  - Sources/GlossPage/InterfacePage.swift (the render entry point, the page's levels, the determinism promise)
  - Sources/GlossPage/PageData.swift (the data the page builds each type's view from)
  - Sources/GlossPage/PageMap.swift (the map figures and module views)
  - Tests/GlossTests/InterfaceTests.swift (rendering is deterministic)
# The one file this video explains: always watched.
explains: "Sources/GlossPage/README.md"

verified: "c2effe0758ea"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order. The narration is the only text sent to TTS, so it is
written for the ear: no identifiers that read badly aloud, short sentences. The intent above the
first scene is never narrated.
-->

# Intent

- **Point:** Gloss Page turns the arranged interface into one HTML file that is the same every time, and shows only what the model holds.
- **Angle:** start with who needs a page that is not the app, then the promise of the same bytes, then how a large page stays openable, then the honest-gap idea.
- **Length:** about a minute, three scenes.
- **Notes:** names come from the sources. Declarations are simplified. The page's direction toward a pull request report comes from the README and is told as a direction, not a feature.

## 01 · one-file — One file to share

> Visual: A node "the app" on the left, dimmed. A node "Atlas" in the middle, and an arrow from it to a node "one HTML file" on the right. Above the arrow, the label "InterfacePage". Under the file node, two pills: "continuous integration" and "sharing". When the narration says never disagree, the arrow from Atlas to the app lights up too.

The gloss app is a window on your Mac. But a build server has no window, and a teammate may want to read the interface without installing anything.

Gloss Page is for them. It renders the arranged interface as one self-contained web page, for continuous integration and for sharing.

It draws from the same Atlas as the app, so the two never disagree.

## 02 · same-bytes — The same bytes every time

> Visual: Two identical boxes labelled "sources" feeding into "render", then into two identical file icons labelled "bytes". Between the files, an equals sign. Below, the mono line "render(interface, assessments:, title:) -> String" marked simplified. Two struck-through pills fade in, "network" and "timestamp".

The page loads nothing from the network, and it stamps no time.

So the same sources always render the same bytes. The tests check exactly that: render twice, and the pages must be equal.

That matters in continuous integration. A saved page diffs cleanly, and a change in the page means a change in the code.

## 03 · by-need — Built when you reach it

> Visual: A big box "every contract as HTML" shown crossed out with the word "too large". Beside it a small box "page data, JSON, once" with an arrow to a card "a type's view". Then a final box "a gap on the page" with an arrow back to "a gap in the model", and a faint pill "pull request report" with an arrow.

Writing every contract out as markup would make a large codebase's page larger than a browser opens comfortably.

So the page embeds its data once, as compact JSON. When a reader reaches a type, the page's script builds that type's view from it. Everything that takes judgment is decided before that, so the script only fills templates.

The page shows only what the model holds. A gap on the page is a gap in the model.

Next, it is shrinking toward a pull request's report of findings and changes.
