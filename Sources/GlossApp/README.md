# GlossApp

The macOS app for reading a package through its interface: a list, a type's details, and its map. It is where gloss is read day to day, drawing from the same arrangement as the page.

<!-- lyceum:video -->
[![GlossApp: reading a package in a window: a narrated explainer](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-app/poster.jpg)](https://pub-cb02f96c3d8442a694d6a124e46839fd.r2.dev/videos/gloss-app/index.html)
<!-- /lyceum:video -->

## Overview

``Workspace`` holds what is open: the folder, its reading, the selection, and the comparison with a base. ``ContentView`` lays out the list, the details, and the map, which ``MapPaneView`` draws and ``MapScroller`` pans and zooms. The details' text scales with ``TextSize``, chosen in ``SettingsView``.

## Topics

### The window

- ``GlossApp``
- ``Workspace``
- ``ContentView``

### The panes

- ``ListPaneView``
- ``DetailPaneView``
- ``MapPaneView``
- ``MapScroller``

### Changes and stories

- ``ChangePageView``
- ``ReachRowView``
- ``StoryThemesView``

### Reading comfort

- ``TextSize``
- ``SettingsView``
