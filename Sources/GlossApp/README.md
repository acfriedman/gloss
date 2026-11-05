# GlossApp

The macOS app for reading a package through its interface: a list, a type's details, and its map. It is where gloss is read day to day, drawing from the same arrangement as the page.

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
