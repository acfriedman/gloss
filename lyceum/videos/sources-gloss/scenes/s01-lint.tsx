import React from "react";
import { C, Arrow, Code, Pill, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: a run and its findings, in compiler format.
const FULL = [
  "$ gloss Sources",
  "Parser.swift:12:5: error: ...",
  "Parser.swift:40:5: warning: ...",
  "Cache.swift:7:5: error: ...",
  "Cache.swift:88:9: warning: ...",
].join("\n");

const CHANGED = [
  "$ gloss --since main Sources",
  "Cache.swift:88:9: warning: ...",
].join("\n");

export const Lint: React.FC = () => {
  const { cue } = useScene();
  const narrow = cue("Two options narrow");
  const fmt = cue("format a compiler uses");
  return (
    <>
      <Text x={960} y={110} size={40} color={C.dim} at={cue("The gloss command")}>the lint</Text>
      <Code code={FULL} x={120} y={240} size={32} at={cue("Point it at a folder")} out={narrow} cps={40}
        highlights={[
          { line: 1, at: fmt, color: ROLE.error },
          { line: 2, at: fmt, color: ROLE.warning },
          { line: 3, at: fmt, color: ROLE.error },
          { line: 4, at: fmt, color: ROLE.warning },
        ]} />
      <Text x={120} y={560} size={32} color={C.dim} anchor="left" at={cue("reports every finding")} out={narrow}>every finding, in the whole of each path</Text>
      <Svg>
        <Arrow from={[1000, 320]} to={[1260, 320]} at={cue("Xcode")} color={C.dim} out={narrow} />
        <Arrow from={[1000, 380]} to={[1260, 440]} at={cue("build server")} color={C.dim} out={narrow} />
        <Arrow from={[1000, 440]} to={[1260, 560]} at={cue("commit hook")} color={C.dim} out={narrow} />
      </Svg>
      <Pill x={1400} y={320} text="Xcode" color={ROLE.consumer} at={cue("So Xcode")} out={narrow} size={34} />
      <Pill x={1400} y={440} text="build server" color={ROLE.consumer} at={cue("build server")} out={narrow} size={34} />
      <Pill x={1400} y={560} text="commit hook" color={ROLE.consumer} at={cue("commit hook")} out={narrow} size={34} />

      <Pill x={560} y={250} text="--staged" color={ROLE.command} at={cue("Staged")} size={36} />
      <Text x={760} y={250} size={30} color={C.dim} anchor="left" at={cue("judges the next commit")}>judges the next commit</Text>
      <Pill x={560} y={340} text="--since <revision>" color={ROLE.command} at={cue("Since takes")} size={36} />
      <Text x={880} y={340} size={30} color={C.dim} anchor="left" at={cue("judges your branch")}>judges your branch against it</Text>
      <Code code={CHANGED} x={120} y={560} size={32} at={cue("Either way")} cps={40}
        highlights={[{ line: 1, at: cue("only findings"), color: ROLE.warning }]} />
      <Text x={120} y={760} size={32} color={ROLE.ok} anchor="left" at={cue("added or changed")}>only declarations the change added or changed</Text>
      <Text x={120} y={830} size={30} color={C.dim} anchor="left" at={cue("still resolve")}>the whole change is read, so links into untouched files resolve</Text>
    </>
  );
};
