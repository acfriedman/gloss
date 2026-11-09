import React from "react";
import { C, Svg, Arrow, Box, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Maps: React.FC = () => {
  const { cue } = useScene();
  const rows = [3, 4, 3];
  return (
    <>
      <Pill x={960} y={110} text="mapBudget = 30 boxes" color={ROLE.map} size={34} at={cue("the budget")} />
      <Node x={400} y={250} w={320} h={90} label="All types" color={ROLE.frontEnd} at={cue("Every type")} />
      <Node x={960} y={250} w={320} h={90} label="Modules" color={ROLE.frontEnd} at={cue("each module as one box")} />
      <Node x={1520} y={250} w={320} h={90} label="One module" color={ROLE.frontEnd} at={cue("steps into a module")} />
      <Svg>
        <Arrow from={[570, 250]} to={[790, 250]} color={C.dim} at={cue("Otherwise each")} />
        <Arrow from={[1130, 250]} to={[1350, 250]} color={C.dim} at={cue("steps into a module")} />
      </Svg>
      <Text x={1520} y={330} size={28} color={C.dim} at={cue("drawn as folders")}>or its folders</Text>
      <Text x={960} y={450} size={34} color={ROLE.map} at={cue("Graph Layout places")}>Graph Layout: rows, top to bottom</Text>
      <Svg>
        {rows.map((n, r) =>
          Array.from({ length: n }, (_, i) => (
            <Box key={`${r}-${i}`} x={960 + (i - (n - 1) / 2) * 200} y={560 + r * 110} w={150} h={70} color={ROLE.map} fill={C.surface} r={10} at={cue("places the boxes in rows")} />
          ))
        )}
        <Box x={1470} y={670} w={150} h={70} color={C.dim} dashed r={10} at={cue("boundary boxes")} />
      </Svg>
      <Text x={1470} y={740} size={26} color={C.dim} at={cue("boundary boxes")}>boundary</Text>
      <Text x={960} y={960} size={34} color={C.text} at={cue("same graph always")}>same graph, same drawing</Text>
    </>
  );
};
