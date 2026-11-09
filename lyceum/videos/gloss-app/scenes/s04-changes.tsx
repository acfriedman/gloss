import React from "react";
import { C, Box, Pill, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Changes: React.FC = () => {
  const { cue } = useScene();
  const bar = cue("changes page");
  const story = cue("A change story");
  const reach = cue("reach row");
  const folded = cue("stays folded");
  return (
    <>
      <Svg>
        <Box x={960} y={250} w={1400} h={80} color={C.dim} fill={C.surface} r={14} at={cue("Compare against")} />
        <Box x={960} y={490} w={1400} h={190} color={ROLE.details} fill={C.surface} r={14} at={story} />
        <Box x={960} y={720} w={1400} h={110} color={ROLE.state} fill={C.surface} r={14} at={reach} />
        <Box x={960} y={860} w={1400} h={110} color={ROLE.state} fill={C.surface} r={14} at={reach} />
      </Svg>
      <Text x={300} y={250} size={34} anchor="left" at={bar}>What changed in Cart</Text>
      <Pill x={1010} y={250} text="new" color={ROLE.rule} at={cue("what is new")} size={26} />
      <Pill x={1130} y={250} text="moved" color={ROLE.state} at={cue("what moved")} size={26} />
      <Pill x={1330} y={250} text="changed inside" color={ROLE.map} at={cue("changed inside")} size={26} />
      <Text x={300} y={440} size={36} weight={700} color={ROLE.details} anchor="left" at={cue("each theme")}>Theme title</Text>
      <Text x={300} y={510} size={30} color={C.dim} anchor="left" at={cue("title over its prose")}>The prose that tells why it changed.</Text>
      <Text x={300} y={720} size={32} anchor="left" at={cue("gives one line")}>One line: how the change reaches the type</Text>
      <Text x={300} y={860} size={32} anchor="left" at={cue("gives one line")}>One line: another way it reaches the type</Text>
      <Text x={1560} y={720} size={30} color={C.dim} at={cue("then the reason")}>▸ reason</Text>
      <Text x={1560} y={860} size={30} color={C.dim} at={folded}>▸ the rest</Text>
      <Text x={1500} y={1000} size={24} color={C.dim} at={0}>illustrative layout</Text>
    </>
  );
};
