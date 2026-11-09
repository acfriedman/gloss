import React from "react";
import { C, Arrow, Code, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Interface: React.FC = () => {
  const { cue } = useScene();
  const json = cue("writes JSON");
  const doc = cue("The JSON holds");
  const same = cue("same index");
  return (
    <>
      <Text x={960} y={110} size={40} color={C.dim} at={cue("export the interface")}>the interface as data</Text>
      <Code code={"$ gloss interface --json out.json Sources"} x={100} y={230} size={32} at={cue("Give it a folder")} cps={40} />
      <Code code={"$ gloss interface --html page.html Sources"} x={100} y={330} size={32} at={cue("web page")} cps={40} />
      <Text x={100} y={440} size={28} color={C.dim} anchor="left" at={cue("standard output")}>no file named: JSON to standard output</Text>
      <Svg>
        <Arrow from={[460, 500]} to={[460, 600]} at={json} color={ROLE.data} />
      </Svg>
      <Node x={460} y={720} w={420} h={90} label="JSON" sub="schema 2" color={ROLE.data} at={json} size={40} />

      <Node x={1330} y={290} w={420} h={80} label="schema" color={C.dim} at={cue("schema number")} size={32} />
      <Node x={1330} y={400} w={420} h={80} label="files" color={ROLE.data} at={cue("files read")} size={32} />
      <Node x={1330} y={510} w={420} h={80} label="contracts" color={ROLE.command} at={cue("one contract")} size={32} />
      <Node x={1330} y={620} w={420} h={80} label="assessments" color={ROLE.warning} at={cue("assessments")} size={32} />
      <Node x={1330} y={730} w={420} h={80} label="graph" color={ROLE.story} at={cue("the graph")} size={32} />
      <Text x={1600} y={565} size={28} color={ROLE.ok} anchor="left" at={same}>same index</Text>
      <Svg>
        <Arrow from={[1560, 610]} to={[1560, 580]} at={same} color={ROLE.ok} />
        <Arrow from={[1560, 580]} to={[1560, 610]} at={same} color={ROLE.ok} />
      </Svg>
      <Text x={1330} y={850} size={30} color={C.dim} at={cue("meet only here")}>the model and the lint meet only here</Text>
      <Text x={1330} y={210} size={32} color={ROLE.data} at={doc}>the document</Text>
    </>
  );
};
