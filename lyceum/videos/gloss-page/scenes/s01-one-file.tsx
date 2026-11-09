import React from "react";
import { C, Svg, Arrow, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const OneFile: React.FC = () => {
  const { cue } = useScene();
  return (
    <>
      <Node x={360} y={500} w={340} h={120} label="the app" sub="a window on your Mac" color={ROLE.app} at={cue("The gloss app")} />
      <Node x={960} y={500} w={300} h={120} label="Atlas" color={ROLE.atlas} at={cue("same Atlas")} />
      <Node x={1560} y={500} w={340} h={120} label="one HTML file" color={ROLE.page} at={cue("Gloss Page")} />
      <Svg>
        <Arrow from={[1110, 500]} to={[1385, 500]} color={ROLE.page} at={cue("It renders")} />
        <Arrow from={[810, 500]} to={[535, 500]} color={ROLE.app} at={cue("never disagree")} />
      </Svg>
      <Text x={1250} y={440} size={30} font="mono" color={ROLE.page} at={cue("It renders")}>InterfacePage</Text>
      <Pill x={1400} y={690} text="continuous integration" color={ROLE.page} size={30} at={cue("continuous integration")} />
      <Pill x={1700} y={770} text="sharing" color={ROLE.page} size={30} at={cue("for sharing", { offset: 0.1 })} />
      <Text x={360} y={690} size={30} color={C.dim} at={cue("a build server has no window")}>no window on a build server</Text>
      <Text x={960} y={900} size={36} color={ROLE.atlas} at={cue("never disagree")}>the two never disagree</Text>
    </>
  );
};
