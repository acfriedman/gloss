import type { SceneMap } from "#kit";
import { Window } from "./s01-window";
import { Workspace } from "./s02-workspace";
import { Comfort } from "./s03-comfort";
import { Changes } from "./s04-changes";

export const scenes: SceneMap = {
  window: Window,
  workspace: Workspace,
  comfort: Comfort,
  changes: Changes,
};
