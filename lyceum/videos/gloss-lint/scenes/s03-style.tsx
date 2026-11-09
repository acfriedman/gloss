import React from "react";
import { C, Arrow, Box, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Style: React.FC = () => {
  const { cue } = useScene();
  const card = cue("house style,");
  const keys: [string, string][] = [
    ["severity", "A rule can be"],
    ["rules", "A prefix such as"],
    ["exclude", "Some paths can be"],
    ["requireDocs", "which declarations owe"],
  ];
  return (
    <>
      <Svg>
        <Box x={560} y={520} w={720} h={500} color={C.dim} fill={C.surface} r={18} at={card} />
        <Arrow from={[930, 520]} to={[1180, 520]} at={cue("A rule can be")} color={ROLE.linter} />
      </Svg>
      <Text x={560} y={330} size={36} font="mono" color={C.text} at={card}>.gloss/style.json</Text>
      {keys.map(([k, phrase], i) => (
        <Text key={k} x={300} y={440 + i * 80} size={38} font="mono" anchor="left" color={C.text} at={cue(phrase)}>{k}</Text>
      ))}
      <Node x={1360} y={520} w={300} h={110} label="Linter" color={ROLE.linter} at={cue("A rule can be")} size={44} />
      <Node x={1360} y={680} w={200} h={64} label="error" color={ROLE.wrong} at={cue("an error, a")} size={30} />
      <Node x={1360} y={770} w={200} h={64} label="warning" color={C.gold} at={cue("a warning,")} size={30} />
      <Node x={1360} y={860} w={200} h={64} label="off" color={C.dim} at={cue("or off")} size={30} />
      <Text x={560} y={880} size={32} color={C.dim} at={cue("With no file")}>no file: every rule an error</Text>
      <Text x={560} y={940} size={32} color={ROLE.wrong} at={cue("A key gloss")}>an unknown key is an error</Text>
    </>
  );
};
