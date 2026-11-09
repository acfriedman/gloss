import type { SceneMap } from "#kit";
import { Once } from "./s01-once";
import { Declaration } from "./s02-declaration";
import { Index } from "./s03-index";
import { Revision } from "./s04-revision";

export const scenes: SceneMap = {
  once: Once,
  declaration: Declaration,
  index: Index,
  revision: Revision,
};
