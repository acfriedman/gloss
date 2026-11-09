import React from "react";
import { C, Svg, Box, Code, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: the doc comment of Interface.build(sources:), trimmed.
const CODE = [
  "/// Reads every source once.",
  "///",
  "/// - Parameter sources: Each file's path",
  "///   and its contents.",
  "/// - Returns: The interface in file order.",
  "static func build(sources:) -> Interface",
].join("\n");

export const Contract: React.FC = () => {
  const { cue } = useScene();
  const sig = cue("signature as written");
  const summary = cue("The summary");
  const params = cue("Each parameter");
  const returns = cue("What it returns");
  const callouts = cue("any callouts");
  const mentions = cue("type names the declaration mentions");
  const fields: [string, number, string][] = [
    ["declaration", sig, C.text],
    ["summary", summary, ROLE.contract],
    ["parameters", params, C.gold],
    ["returns", returns, C.green],
    ["throwsDoc", cue("what it throws"), C.red],
    ["callouts", callouts, C.purple],
    ["mentions", mentions, ROLE.graph],
  ];
  return (
    <>
      <Text x={960} y={140} size={40} color={C.dim} at={cue("Gloss Model reads")}>one declaration, simplified</Text>
      <Code code={CODE} x={80} y={330} size={26} at={cue("For every declaration")} cps={60}
        highlights={[
          { line: 5, at: sig, color: C.text },
          { line: 0, at: summary, color: ROLE.contract },
          { line: 2, to: 40, at: params, color: C.gold },
          { line: 4, at: returns, color: C.green },
        ]} />
      <Svg>
        <Box x={1440} y={560} w={800} h={640} color={ROLE.contract} fill={C.surface} r={16} at={cue("builds a Contract")} />
      </Svg>
      <Text x={1440} y={290} size={44} color={ROLE.contract} at={cue("builds a Contract")}>Contract</Text>
      {fields.map(([name, at, color], i) => (
        <Text key={name} x={1110} y={370 + i * 70} size={32} font="mono" anchor="left" color={color} at={at}>{name}</Text>
      ))}
    </>
  );
};
