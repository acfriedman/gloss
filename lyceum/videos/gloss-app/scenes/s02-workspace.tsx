import React from "react";
import { C, Arrow, Box, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Workspace: React.FC = () => {
  const { cue } = useScene();
  const rows: [string, string][] = [
    ["folder", "folder,"],
    ["reading", "reading of that"],
    ["selection", "selection,"],
    ["comparison with a base", "comparison with"],
  ];
  const atlas = cue("makes no decisions");
  const page = cue("the page uses");
  return (
    <>
      <Svg>
        <Box x={640} y={470} w={600} h={420} color={ROLE.state} fill={C.surface} r={18} at={cue("called Workspace")} />
        <Arrow from={[1190, 470]} to={[960, 470]} at={atlas} color={ROLE.rule} />
        <Arrow from={[1400, 540]} to={[1400, 700]} at={page} color={ROLE.rule} />
      </Svg>
      <Text x={640} y={320} size={46} color={ROLE.state} at={cue("called Workspace")}>Workspace</Text>
      {rows.map(([label, phrase], i) => (
        <Text key={label} x={400} y={410 + i * 70} size={36} anchor="left" at={cue(phrase)}>{label}</Text>
      ))}
      <Node x={1400} y={470} w={420} h={120} label="Atlas" color={ROLE.rule} at={atlas} size={44} />
      <Text x={1400} y={520} size={26} color={C.dim} at={atlas}>from Gloss Map</Text>
      <Node x={1400} y={780} w={420} h={110} label="the page" color={ROLE.details} at={page} size={40} />
      <Text x={960} y={960} size={36} color={C.dim} at={cue("never disagree")}>one arrangement, two readers</Text>
    </>
  );
};
