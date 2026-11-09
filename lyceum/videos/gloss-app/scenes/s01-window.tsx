import React from "react";
import { C, Box, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Boxes stand for the panes; they are not screenshots of the app.
export const Window: React.FC = () => {
  const { cue } = useScene();
  const list = cue("A list on the left");
  const details = cue("The details of whatever");
  const map = cue("And a map");
  const tabs = cue("bar of tabs");
  return (
    <>
      <Svg>
        <Box x={960} y={580} w={1560} h={640} color={C.dim} fill={C.surface} r={22} at={0} />
      </Svg>
      <Text x={960} y={300} size={34} color={C.dim} font="mono" at={cue("window has three panes")}>gloss</Text>
      <Node x={400} y={620} w={300} h={480} label="List" color={ROLE.list} at={list} size={40} />
      <Node x={880} y={660} w={540} h={400} label="Details" color={ROLE.details} at={details} size={40} />
      <Node x={1440} y={660} w={540} h={400} label="Map" color={ROLE.map} at={map} size={40} />
      <Node x={1160} y={400} w={1100} h={56} label="tabs" color={ROLE.state} at={tabs} size={30} />
    </>
  );
};
