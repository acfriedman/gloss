# Give every README a narrated video that keeps itself current

A README says what a module is for, but a reader new to gloss has to hold its whole vocabulary at once.
Each README now gets a short narrated video, made with Lyceum from the code it describes. CI keeps the
videos current with no one reviewing them, so they can't drift the way docs do.

## A video for every README

`lyceum/` is a Lyceum project whose coverage is every `README.md` in the repository: the root and each
module's page. Its guide, `lyceum/project.md`, tells the agent who watches, where ground truth lives,
and how gloss's names are spoken.

Each video is published to the project's R2 bucket at fixed URLs. Its README shows it as a thumbnail
between `lyceum:video` markers, placed after the page's summary. gloss's module-page reading skips
everything between the summary and `## Overview`, so the block changes neither the summary nor the
lint.

## Refreshed by CI, unreviewed

`.github/workflows/lyceum.yml` runs on every push to main, weekly, and by hand. Claude Code revises or
makes each video that needs it, `lyceum ship` publishes it only if every gate passes, and the result
lands as a pull request that merges itself.

The bot's branches, `lyceum/refresh-*`, change no Swift declarations, so they carry no change story.
A video that fails a gate keeps its last published copy, and the run opens an issue.

## Secrets stay out of git

`.env` is ignored. It holds the store's keys for local runs, and it had been left untracked in the
repository's root.

`.claude/settings.json` gains Lyceum's session-start check, which says when a newer Lyceum release
is out.
