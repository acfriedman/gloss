import React from "react";
import { C, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: the real table has a row for every phase; the figures vary per run.
const ROWS = [
  ["read files", "reads the files"],
  ["map levels", "lays out every level"],
  ["trails", "the busiest types"],
  ["highlight members", "the busiest types"],
];

export const Bench: React.FC = () => {
  const { cue } = useScene();
  const table = cue("prints a table");
  const rows = [cue("reads the files"), cue("builds the map"), cue("lays out every level"), cue("busiest types")];
  const status = cue("keeps its promises");
  return (
    <>
      <Text x={960} y={110} size={40} color={C.dim} at={cue("the bench")}>gloss bench</Text>
      <Text x={120} y={230} size={30} font="mono" color={ROLE.command} anchor="left" at={table}>phase</Text>
      <Text x={760} y={230} size={30} font="mono" color={ROLE.command} anchor="left" at={cue("how many times")}>runs</Text>
      <Text x={960} y={230} size={30} font="mono" color={ROLE.command} anchor="left" at={cue("in all")}>total ms</Text>
      <Text x={1260} y={230} size={30} font="mono" color={ROLE.command} anchor="left" at={cue("slowest run")}>max ms</Text>
      <Text x={1520} y={230} size={30} font="mono" color={ROLE.command} anchor="left" at={cue("slowest run")}>slowest</Text>
      {ROWS.map(([name], i) => (
        <React.Fragment key={name}>
          <Text x={120} y={300 + i * 65} size={30} font="mono" anchor="left" at={rows[i]}>{name}</Text>
          <Text x={760} y={300 + i * 65} size={30} font="mono" color={C.dim} anchor="left" at={rows[i]}>-</Text>
          <Text x={960} y={300 + i * 65} size={30} font="mono" color={C.dim} anchor="left" at={rows[i]}>-</Text>
          <Text x={1260} y={300 + i * 65} size={30} font="mono" color={C.dim} anchor="left" at={rows[i]}>-</Text>
        </React.Fragment>
      ))}
      <Text x={960} y={610} size={30} color={C.dim} at={cue("A slow phase")}>a slow phase shows at a glance</Text>

      <Text x={120} y={700} size={34} color={ROLE.command} anchor="left" at={status}>exit statuses</Text>
      <Pill x={300} y={790} text="0  no errors" color={ROLE.ok} at={cue("exits with one only")} size={30} />
      <Pill x={640} y={790} text="1  errors" color={ROLE.error} at={cue("exits with one only")} size={30} />
      <Pill x={980} y={790} text="64  usage" color={ROLE.warning} at={cue("A missing value")} size={30} />
      <Pill x={1380} y={790} text="65  style file broken" color={ROLE.warning} at={cue("A broken style file")} size={30} />
      <Pill x={900} y={890} text="66  no such path" color={ROLE.error} at={cue("a path that does not exist")} size={30} />
    </>
  );
};
