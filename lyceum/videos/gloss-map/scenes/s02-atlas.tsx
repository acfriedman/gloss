import React from "react";
import { C, Svg, Arrow, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Atlas: React.FC = () => {
  const { cue } = useScene();
  const pills = [
    { t: "levels", p: "The levels of the map" },
    { t: "focus", p: "The focus" },
    { t: "reaches", p: "What a type reaches" },
    { t: "why", p: "why one type uses another" },
  ];
  return (
    <>
      <Node x={330} y={300} w={380} h={110} label="Contract" sub="a declaration as read" color={ROLE.frontEnd} at={cue("takes each contract")} />
      <Node x={330} y={560} w={380} h={110} label="Assessment" sub="the lint's verdict" color={ROLE.lint} at={cue("lint's assessment")} />
      <Node x={900} y={430} w={300} h={130} label="Atlas" color={ROLE.map} at={cue("The Atlas is where")} />
      <Svg>
        <Arrow from={[520, 330]} to={[750, 410]} color={C.dim} at={cue("takes each contract")} />
        <Arrow from={[520, 530]} to={[750, 460]} color={C.dim} at={cue("lint's assessment")} />
      </Svg>
      {pills.map((q, i) => (
        <Pill key={q.t} x={1450} y={290 + i * 90} text={q.t} color={ROLE.map} size={34} at={cue(q.p)} />
      ))}
      <Text x={960} y={800} size={34} font="mono" color={C.text} at={cue("called a reviewed contract")}>{"struct Reviewed { contract; assessment }"}</Text>
      <Text x={960} y={860} size={26} color={C.dim} at={cue("called a reviewed contract")}>simplified</Text>
      <Text x={960} y={950} size={34} color={ROLE.lint} at={cue("The lint is optional")}>the lint is optional: no lint, no findings</Text>
    </>
  );
};
