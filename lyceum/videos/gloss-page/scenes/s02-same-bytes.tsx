import React from "react";
import { C, Svg, Arrow, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const SameBytes: React.FC = () => {
  const { cue } = useScene();
  return (
    <>
      <Node x={400} y={330} w={300} h={100} label="same sources" color={ROLE.model} at={cue("the same sources")} />
      <Node x={960} y={330} w={300} h={100} label="render" color={ROLE.page} at={cue("always render")} />
      <Node x={1500} y={250} w={300} h={90} label="bytes" color={ROLE.atlas} at={cue("the same bytes")} />
      <Node x={1500} y={410} w={300} h={90} label="bytes" color={ROLE.atlas} at={cue("render twice")} />
      <Text x={1500} y={330} size={48} color={C.text} at={cue("must be equal")}>=</Text>
      <Svg>
        <Arrow from={[550, 330]} to={[810, 330]} color={C.dim} at={cue("always render")} />
        <Arrow from={[1110, 310]} to={[1345, 255]} color={C.dim} at={cue("the same bytes")} />
        <Arrow from={[1110, 350]} to={[1345, 405]} color={C.dim} at={cue("render twice")} />
      </Svg>
      <Pill x={700} y={560} text="network" color={ROLE.no} size={32} at={cue("loads nothing")} />
      <Pill x={1000} y={560} text="timestamp" color={ROLE.no} size={32} at={cue("stamps no time")} />
      <Text x={850} y={640} size={28} color={C.dim} at={cue("loads nothing")}>neither goes on the page</Text>
      <Text x={960} y={780} size={34} font="mono" color={C.text} at={cue("The tests check")}>{"render(interface, assessments:, title:) -> String"}</Text>
      <Text x={960} y={830} size={26} color={C.dim} at={cue("The tests check")}>simplified</Text>
      <Text x={960} y={950} size={36} color={ROLE.page} at={cue("diffs cleanly")}>a change in the page is a change in the code</Text>
    </>
  );
};
