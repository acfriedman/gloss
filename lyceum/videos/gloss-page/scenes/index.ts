import type { SceneMap } from "#kit";
import { OneFile } from "./s01-one-file";
import { SameBytes } from "./s02-same-bytes";
import { ByNeed } from "./s03-by-need";

export const scenes: SceneMap = {
  "one-file": OneFile,
  "same-bytes": SameBytes,
  "by-need": ByNeed,
};
