---
title: "GlossApp: reading a package in a window"
status: draft 1
updated: 2026-11-09
# Written form → spoken form, applied only to the text sent to the voice.
pronounce: {}
# Subtitles: a track viewers turn on, or `captions: burned` to draw them into the picture.
# captions: burned
# The look: the dark canvas, or `theme: paper`, a light, formal look for presentations.
# theme: paper
# The files this video explains, one per line: `- path (what the video takes from it)`.
# `lyceum stale` watches them; `lyceum stale --mark gloss-app` records the commit they were checked at.
sources:
  - Sources/GlossApp/README.md (the page told: the panes, the workspace, text size)
  - Sources/GlossApp/GlossApp.swift (the window, the welcome window, the menus)
  - Sources/GlossApp/Workspace.swift (what is open, the selection, the comparison)
  - Sources/GlossApp/ContentView.swift (the list, details and map layout)
  - Sources/GlossApp/MapScroller.swift (wheel zoom and right-button pan)
  - Sources/GlossApp/TextSize.swift (the text scale and its steps)
  - Sources/GlossApp/SettingsView.swift (the text size setting)
  - Sources/GlossApp/ChangePageView.swift (a change's page and its reaches)
  - Sources/GlossApp/StoryView.swift (the story on a type's page)
# The one file this video explains: always watched, and `lyceum embed gloss-app` shows the video in it.
explains: "Sources/GlossApp/README.md"
---

<!--
Format: one `## NN · id — Title` per scene. `> Visual:` lines describe the animation; every other
paragraph is narration, spoken in order. The narration is the only text sent to TTS, so it is
written for the ear: no identifiers that read badly aloud, short sentences. The intent above the
first scene is never narrated.
-->

# Intent

- **Point:** GlossApp is where gloss is read day to day: a list, a type's details and a map, all drawn from the same arrangement as the page, so the app and the page never disagree.
- **For:** the project's audience; contributors about to work in the module will find the types the page names.
- **Angle:** start with the window and its three panes, then what holds the reader's place, then how the map and the text are made comfortable, then how changes are read.
- **Length:** about a minute and a half, four scenes.
- **Notes:** the app cannot run in CI, so it is described from its code and page, never shown as screens. Boxes and labels stand for the panes; they are not screenshots.

## 01 · window — Three panes

> Visual: A wide rounded window frame, titled "gloss". Three labelled panels slide in left to right as each is named: "List", "Details", "Map". Above the details and map a thin bar labelled "tabs".

GlossApp is the macOS app for gloss. It is where you read a package through its interface, day to day.

The window has three panes. A list on the left. The details of whatever is selected in the middle. And a map on the right.

The details and the map sit under a bar of tabs, as they do in Xcode.

## 02 · workspace — What is open

> Visual: A card labelled "Workspace" in the centre. Four rows appear in turn: "folder", "reading", "selection", "comparison with a base". Below it a box labelled "Atlas, from Gloss Map" with an arrow into the Workspace card, and a second arrow out of the Atlas to a box labelled "the page".

One object holds what is open. It is called Workspace.

It remembers the folder, the reading of that folder, the selection, and the comparison with a base.

It makes no decisions about what to show. Those come from the same arrangement the page uses. So the app and the page never disagree about the system.

## 03 · comfort — The map and the text

> Visual: The map panel on the left with a mouse wheel icon zooming it, then a right-button drag panning it. On the right a row of seven text-size steps from 85 percent to 200 percent, with 100 percent marked "the system's". Below, the line "public struct Cart" growing as steps are picked.

The map moves like a canvas. The mouse wheel zooms toward the pointer. Dragging with the right button pans. The left button is left free to click and select.

The text in the details can be made bigger or smaller. There are seven steps, from a little smaller to twice as big. The second is the size macOS itself uses.

You choose a step in Settings, or from the View menu. The list and the map keep their sizes.

## 04 · changes — Reading a change

> Visual: A changes page: a headline bar reading "What changed in Cart", under it a theme card with a title over a line of prose, and two reach rows beneath, each with one line shown and the rest folded under a small chevron.

The app also reads changes. Compare against a base, and the changes page shows what is new, what moved, and what changed inside.

A change story appears on the page of each type it explains: each theme, with its title over its prose.

And for every way a change reaches a type, a reach row gives one line, then the reason. The rest stays folded until you ask.
