import React from "react";
import { C, Svg, Arrow, Node, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const OneArrangement: React.FC = () => {
  const { cue } = useScene();
  return (
    <>
      <Node x={600} y={260} w={380} h={110} label="the app" color={ROLE.frontEnd} at={cue("two front ends")} />
      <Node x={1320} y={260} w={380} h={110} label="the page" color={ROLE.frontEnd} at={cue("the page")} />
      <Text x={960} y={420} size={34} color={C.dim} at={cue("show the same code")}>the same code</Text>
      <Node x={960} y={760} w={520} h={130} label="Gloss Map" color={ROLE.map} at={cue("So Gloss Map")} />
      <Svg>
        <Arrow from={[700, 330]} to={[860, 695]} color={C.dim} at={cue("both front ends draw")} />
        <Arrow from={[1220, 330]} to={[1060, 695]} color={C.dim} at={cue("both front ends draw")} />
      </Svg>
      <Text x={960} y={920} size={36} color={ROLE.map} at={cue("decides once")}>decides once</Text>
    </>
  );
};
