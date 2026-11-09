import type { SceneMap } from "#kit";
import { Contract } from "./s01-contract";
import { Graph } from "./s02-graph";
import { Diff } from "./s03-diff";
import { Story } from "./s04-story";

export const scenes: SceneMap = {
  contract: Contract,
  graph: Graph,
  diff: Diff,
  story: Story,
};
