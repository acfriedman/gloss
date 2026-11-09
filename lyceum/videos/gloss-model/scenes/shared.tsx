// The visual vocabulary this video reuses across scenes, so the same idea always looks the same:
// role colours, standard positions, and recurring props.

import { C } from "#kit";

export const ROLE = {
  contract: C.blue,
  graph: C.green,
  reason: C.gold,
  diff: C.purple,
  story: C.teal,
  wrong: C.red,
} as const;
