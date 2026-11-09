import type { SceneMap } from "#kit";
import { Hook } from "./s01-hook";
import { Shape } from "./s02-shape";
import { OnePass } from "./s03-one-pass";
import { Story } from "./s04-story";
import { Layers } from "./s05-layers";

export const scenes: SceneMap = {
  hook: Hook,
  shape: Shape,
  "one-pass": OnePass,
  story: Story,
  layers: Layers,
};
