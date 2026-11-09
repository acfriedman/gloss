// The registry: one entry per video directory. `lyceum scenes <video>` adds a video's narration
// and scene map here.

import type { Narration, SceneMap } from "#kit";
import glossNarration from "./gloss/narration.json";
import { scenes as glossScenes } from "./gloss/scenes";
import glossAppNarration from "./gloss-app/narration.json";
import { scenes as glossAppScenes } from "./gloss-app/scenes";
import glossLintNarration from "./gloss-lint/narration.json";
import { scenes as glossLintScenes } from "./gloss-lint/scenes";
import glossMapNarration from "./gloss-map/narration.json";
import { scenes as glossMapScenes } from "./gloss-map/scenes";
import glossModelNarration from "./gloss-model/narration.json";
import { scenes as glossModelScenes } from "./gloss-model/scenes";
import glossPageNarration from "./gloss-page/narration.json";
import { scenes as glossPageScenes } from "./gloss-page/scenes";
import glossReadNarration from "./gloss-read/narration.json";
import { scenes as glossReadScenes } from "./gloss-read/scenes";
import sourcesGlossNarration from "./sources-gloss/narration.json";
import { scenes as sourcesGlossScenes } from "./sources-gloss/scenes";

export const videos: { narration: Narration; scenes: SceneMap }[] = [
  { narration: glossNarration as Narration, scenes: glossScenes },
  { narration: glossAppNarration as Narration, scenes: glossAppScenes },
  { narration: glossLintNarration as Narration, scenes: glossLintScenes },
  { narration: glossMapNarration as Narration, scenes: glossMapScenes },
  { narration: glossModelNarration as Narration, scenes: glossModelScenes },
  { narration: glossPageNarration as Narration, scenes: glossPageScenes },
  { narration: glossReadNarration as Narration, scenes: glossReadScenes },
  { narration: sourcesGlossNarration as Narration, scenes: sourcesGlossScenes },
];
