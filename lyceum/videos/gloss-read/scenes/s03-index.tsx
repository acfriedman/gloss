import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Index: React.FC = () => {
  const { cue } = useScene();
  const index = cue("an index of everything");
  const link = cue("A link in one file");
  const headers = cue("headers ride along");
  const names = cue("Only the type names");
  const page = cue("a module's page");
  const cores = cue("over every core");
  return (
    <>
      <Svg>
        <Arrow from={[520, 300]} to={[780, 520]} at={index} color={C.text} />
        <Arrow from={[520, 520]} to={[780, 540]} at={headers} color={C.text} />
        <Arrow from={[520, 740]} to={[780, 560]} at={page} color={C.text} />
        <Arrow from={[1140, 540]} to={[1400, 540]} at={link} color={ROLE.index} />
      </Svg>
      <Node x={320} y={300} w={400} h={110} label="Swift files" sub="declarations" color={ROLE.read} at={cue("The Reading also holds")} size={36} />
      <Node x={320} y={520} w={400} h={110} label="Objective-C headers" color={ROLE.git} at={headers} size={32} />
      <Node x={320} y={740} w={400} h={110} label="Module pages" sub="read as pages" color={ROLE.doc} at={page} size={36} />
      <Node x={960} y={540} w={360} h={140} label="Symbol Index" color={ROLE.index} at={index} size={40} />
      <Text x={320} y={620} size={28} color={C.dim} at={names}>type names only, not parsed</Text>
      <Text x={1640} y={440} size={34} font="mono" color={ROLE.index} at={link}>``Reading``</Text>
      <Text x={1640} y={540} size={64} color={C.green} at={cue("checked against all", { after: link })}>✓</Text>
      <Text x={1640} y={640} size={28} color={C.dim} at={link}>resolves in any file</Text>
      <Text x={960} y={900} size={30} color={C.dim} at={cores}>Swift files read in parallel, then indexed</Text>
    </>
  );
};
