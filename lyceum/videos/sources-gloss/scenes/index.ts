import type { SceneMap } from "#kit";
import { Lint } from "./s01-lint";
import { Interface } from "./s02-interface";
import { Story } from "./s03-story";
import { Bench } from "./s04-bench";

export const scenes: SceneMap = {
  lint: Lint,
  interface: Interface,
  story: Story,
  bench: Bench,
};
