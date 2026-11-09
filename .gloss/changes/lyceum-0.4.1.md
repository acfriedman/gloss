# Let the video workflow's agent read its task

The first run of the video workflow failed before any video was made. Claude Code never got its prompt:
Lyceum passed the prompt after `--allowedTools`, which takes any number of values and read it as one
more tool. Lyceum 0.4.1 sends the prompt on stdin, and `lyceum/` now depends on it.

## Lyceum 0.4.1

`lyceum/package.json` asks for `^0.4.1`, and the lockfile pins its commit. No Swift declaration changes.
