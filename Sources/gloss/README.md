# gloss

The command line: it lints, exports the interface, checks a branch's story, and times the app's work. Its findings print in compiler format, so Xcode, CI, and a commit hook use them as is.

## Overview

The lint reads the whole of each path and reports every finding, or, with `--staged` and `--since`, only those on what a change touched, through ``ChangeLint``. ``Export`` writes the interface as JSON, ``StoryCheck`` runs `gloss story`, and ``Bench`` times each phase of the app's work.

## Topics

### Commands

- ``ChangeLint``
- ``StoryCheck``
- ``Export``
- ``Bench``
