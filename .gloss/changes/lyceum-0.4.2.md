# Let the video workflow draw, and finish what it started

The second run of the video workflow wrote three videos but couldn't draw a frame: Chrome won't start on
GitHub's Ubuntu 24.04 runners, whose AppArmor setting blocks its sandbox. Lyceum 0.4.2 lets the sandbox
work, and it retries a video whose drafts landed but never went out.

## Lyceum 0.4.2

The workflow, regenerated from Lyceum's template, relaxes the AppArmor setting on the runner for the
job, so Chrome keeps its sandbox. Its plan now counts a video as needing work until its current version
is published, so the three drafts from the last run come first.

## One video a run

The workflow takes one video a run by default instead of three, so each run reports back in minutes
while the loop beds in. A run started by hand can still ask for more.
