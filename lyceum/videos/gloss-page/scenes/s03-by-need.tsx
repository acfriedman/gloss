import React from "react";
import { C, Svg, Arrow, Node, Pill, Text, Line, useScene } from "#kit";
import { ROLE } from "./shared";

export const ByNeed: React.FC = () => {
  const { cue } = useScene();
  return (
    <>
      <Node x={420} y={300} w={460} h={110} label="every contract as markup" color={ROLE.no} at={cue("Writing every contract")} />
      <Text x={420} y={400} size={30} color={ROLE.no} at={cue("larger than a browser")}>larger than a browser opens comfortably</Text>
      <Node x={420} y={560} w={420} h={100} label="page data" sub="compact JSON, once" color={ROLE.page} at={cue("embeds its data once")} />
      <Node x={1000} y={560} w={380} h={100} label="a type's view" sub="built when you reach it" color={ROLE.atlas} at={cue("reaches a type")} />
      <Svg>
        <Line from={[200, 270]} to={[640, 330]} color={ROLE.no} at={cue("larger than a browser")} />
        <Arrow from={[630, 560]} to={[810, 560]} color={C.dim} at={cue("builds that type's view")} />
      </Svg>
      <Pill x={1500} y={560} text="script only fills templates" color={ROLE.page} size={28} at={cue("only fills templates")} />
      <Node x={560} y={830} w={340} h={100} label="a gap on the page" color={ROLE.page} at={cue("A gap on the page")} />
      <Node x={1060} y={830} w={340} h={100} label="a gap in the model" color={ROLE.model} at={cue("a gap in the model")} />
      <Svg>
        <Arrow from={[730, 830]} to={[890, 830]} color={C.dim} at={cue("a gap in the model")} />
      </Svg>
      <Pill x={1620} y={830} text="pull request report" color={C.gold} size={28} at={cue("pull request's report")} />
      <Text x={1620} y={885} size={24} color={C.dim} at={cue("pull request's report")}>where it is heading</Text>
    </>
  );
};
