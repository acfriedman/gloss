import React from "react";
import { C, Svg, Arrow, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Change: React.FC = () => {
  const { cue } = useScene();
  return (
    <>
      <Node x={600} y={300} w={240} h={90} label="user" color={ROLE.map} at={cue("what uses it")} />
      <Node x={600} y={700} w={240} h={90} label="dependency" color={ROLE.map} at={cue("what a type depends on")} />
      <Node x={600} y={500} w={280} h={100} label="changed" color={ROLE.change} at={cue("types that changed")} />
      <Svg>
        <Arrow from={[600, 350]} to={[600, 445]} color={C.dim} at={cue("what uses it")} />
        <Arrow from={[600, 552]} to={[600, 655]} color={C.dim} at={cue("what a type depends on")} />
      </Svg>
      <Pill x={600} y={170} text="above: what uses it" color={C.dim} size={26} at={cue("or both")} />
      <Pill x={600} y={850} text="below: what it depends on" color={C.dim} size={26} at={cue("or both")} />
      <Node x={1350} y={380} w={560} h={90} label="why it changed" sub="from the branch's story" color={ROLE.change} at={cue("Why the thing it relies on changed")} />
      <Node x={1350} y={520} w={560} h={90} label="why it relies on it" sub="from the docs" color={ROLE.frontEnd} at={cue("why it relies on that thing")} />
      <Text x={1350} y={720} size={34} font="mono" color={ROLE.lint} at={cue("Changed Findings keeps")}>ChangedFindings</Text>
      <Pill x={1350} y={790} text="only touched declarations" color={ROLE.lint} size={28} at={cue("added or changed")} />
      <Text x={1350} y={900} size={32} color={C.dim} at={cue("Code nobody touched")}>untouched code can't fail the change</Text>
    </>
  );
};
