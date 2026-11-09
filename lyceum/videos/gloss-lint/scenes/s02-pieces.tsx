import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Pieces: React.FC = () => {
  const { cue } = useScene();
  const rules = cue("the Rules");
  const diag = cue("Every finding");
  const codes: [string, string][] = [
    ["missing-doc", "A missing doc comment"],
    ["summary-opener", "A summary that opens"],
    ["returns-missing", "A function that returns"],
  ];
  return (
    <>
      <Svg>
        <Arrow from={[500, 400]} to={[760, 400]} at={rules} color={ROLE.rules} />
        <Arrow from={[1160, 400]} to={[1420, 400]} at={diag} color={ROLE.finding} />
      </Svg>
      <Node x={360} y={400} w={280} h={120} label="Linter" color={ROLE.linter} at={cue("The Linter is")} size={44} />
      <Node x={960} y={400} w={360} h={120} label="Rules" color={ROLE.rules} at={rules} size={44} />
      <Node x={1560} y={400} w={280} h={120} label="Diagnostic" color={ROLE.finding} at={diag} size={40} />
      <Text x={630} y={340} size={26} color={C.dim} at={rules}>each declaration</Text>
      <Text x={1290} y={340} size={26} color={C.dim} at={diag}>each finding</Text>
      {codes.map(([code, phrase], i) => (
        <Text key={code} x={960} y={600 + i * 70} size={36} font="mono" color={ROLE.rules} at={cue(phrase)}>{code}</Text>
      ))}
      <Text x={1560} y={560} size={28} color={C.dim} at={cue("renders itself")}>file:line:column: … [rule]</Text>
    </>
  );
};
