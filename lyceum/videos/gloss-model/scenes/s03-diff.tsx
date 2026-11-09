import React from "react";
import { C, Line, Pill, Svg, Box, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Diff: React.FC = () => {
  const { cue } = useScene();
  const start = cue("compares two interfaces");
  const byName = cue("matched by name");
  const kinds: [string, string, number, number][] = [
    ["added", C.green, 230, cue("Added")],
    ["removed", C.red, 540, cue("Removed")],
    ["changed", C.gold, 850, cue("Changed")],
    ["implementation", C.purple, 1240, cue("Implementation")],
    ["moved", C.blue, 1660, cue("And moved")],
  ];
  return (
    <>
      <Svg>
        <Box x={480} y={400} w={620} h={300} color={C.dim} fill={C.surface} r={16} at={start} />
        <Box x={1440} y={400} w={620} h={300} color={ROLE.diff} fill={C.surface} r={16} at={start} />
        <Line from={[700, 360]} to={[1220, 440]} at={byName} color={C.dim} />
        <Line from={[700, 440]} to={[1220, 360]} at={byName} color={C.dim} />
      </Svg>
      <Text x={480} y={290} size={34} color={C.dim} at={start}>base</Text>
      <Text x={1440} y={290} size={34} color={ROLE.diff} at={start}>head</Text>
      <Text x={300} y={360} size={30} font="mono" anchor="left" color={C.text} at={start}>load()</Text>
      <Text x={300} y={440} size={30} font="mono" anchor="left" color={C.text} at={start}>save()</Text>
      <Text x={1260} y={360} size={30} font="mono" anchor="left" color={C.text} at={start}>save()</Text>
      <Text x={1260} y={440} size={30} font="mono" anchor="left" color={C.text} at={start}>load()</Text>
      <Text x={960} y={600} size={30} color={C.dim} at={cue("Code that only moves")}>only the place differs: no change</Text>
      {kinds.map(([text, color, x, at]) => (
        <Pill key={text} x={x} y={760} text={text} color={color} at={at} size={32} />
      ))}
      <Text x={960} y={900} size={32} font="mono" color={C.dim} at={cue("A renamed type")}>Loader → Reader  =  removed Loader, added Reader</Text>
    </>
  );
};
