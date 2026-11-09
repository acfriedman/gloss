import React from "react";
import { C, Arrow, Line, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Apart: React.FC = () => {
  const { cue } = useScene();
  const model = cue("contract model");
  const assess = cue("is the Assessment");
  return (
    <>
      <Svg>
        <Line from={[760, 420]} to={[1160, 420]} dashed color={C.dim} at={model} />
        <Arrow from={[760, 720]} to={[1160, 720]} at={cue("views take")} color={ROLE.app} />
      </Svg>
      <Node x={480} y={420} w={560} h={150} label="Gloss Lint" color={ROLE.linter} at={cue("Nothing in")} size={46} />
      <Node x={1440} y={420} w={560} h={150} label="contract model" color={ROLE.app} at={model} size={44} />
      <Text x={960} y={370} size={26} color={C.dim} at={model}>no link</Text>
      <Node x={480} y={720} w={420} h={110} label="Assessment" color={ROLE.finding} at={assess} size={42} />
      <Node x={1440} y={720} w={420} h={110} label="the app's views" color={ROLE.app} at={cue("views take")} size={38} />
      <Text x={960} y={920} size={38} color={C.dim} at={cue("That is all")}>checks the prose, in a line any tool can read</Text>
    </>
  );
};
