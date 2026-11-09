// The registry: one entry per video directory. `lyceum scenes <video>` adds a video's narration
// and scene map here.

import type { Narration, SceneMap } from "#kit";
import glossNarration from "./gloss/narration.json";
import { scenes as glossScenes } from "./gloss/scenes";
import glossAppNarration from "./gloss-app/narration.json";
import { scenes as glossAppScenes } from "./gloss-app/scenes";
import glossLintNarration from "./gloss-lint/narration.json";
import { scenes as glossLintScenes } from "./gloss-lint/scenes";

export const videos: { narration: Narration; scenes: SceneMap }[] = [
  { narration: glossNarration as Narration, scenes: glossScenes },
  { narration: glossAppNarration as Narration, scenes: glossAppScenes },
  { narration: glossLintNarration as Narration, scenes: glossLintScenes },
];
