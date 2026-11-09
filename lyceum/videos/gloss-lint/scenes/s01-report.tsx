import React from "react";
import { C, Svg, Box, Text, useScene } from "#kit";
import { ROLE } from "./shared";

const W = 18; // mono advance at size 30
const X0 = 150;

export const Report: React.FC = () => {
  const { cue } = useScene();
  const parts: { s: string; color: string; label: string; phrase: string }[] = [
    { s: "Store.swift", color: C.teal, label: "file", phrase: "The file," },
    { s: ":1:1", color: C.blue, label: "line, column", phrase: "the line," },
    { s: ": ", color: C.dim, label: "", phrase: "" },
    { s: "error", color: ROLE.wrong, label: "severity", phrase: "the severity," },
    { s: ": ", color: C.dim, label: "", phrase: "" },
    { s: 'Do not open with "This method"; name the behavior directly', color: C.text, label: "the fix", phrase: "then the fix," },
    { s: " ", color: C.dim, label: "", phrase: "" },
    { s: "[summary-opener]", color: ROLE.finding, label: "rule code", phrase: "rule code in" },
  ];
  let off = 0;
  const placed = parts.map((p) => {
    const x = X0 + off * W;
    off += p.s.length;
    return { ...p, x, w: p.s.length * W };
  });
  return (
    <>
      <Svg>
        <Box x={960} y={300} w={820} h={190} color={C.dim} fill={C.surface} r={16} at={cue("Take a comment")} />
      </Svg>
      <Text x={600} y={270} size={34} font="mono" anchor="left" color={C.text} at={cue("Take a comment")}>/// This method records it.</Text>
      <Text x={600} y={330} size={34} font="mono" anchor="left" color={C.dim} at={cue("Take a comment")}>{"func f() { }"}</Text>
      <Text x={960} y={190} size={36} color={C.dim} at={cue("Gloss Lint checks")}>a doc comment</Text>
      {placed.map((p, i) => (
        <React.Fragment key={i}>
          <Text x={p.x} y={560} size={30} font="mono" anchor="left" color={p.color} at={p.phrase ? cue(p.phrase) : cue("reports it in")}>{p.s}</Text>
          {p.label && (
            <Text x={p.x + p.w / 2} y={620} size={26} color={p.color} at={cue(p.phrase)}>{p.label}</Text>
          )}
        </React.Fragment>
      ))}
      <Text x={960} y={820} size={40} color={C.dim} at={cue("Because it looks like")}>Xcode · continuous integration · a commit hook</Text>
    </>
  );
};
