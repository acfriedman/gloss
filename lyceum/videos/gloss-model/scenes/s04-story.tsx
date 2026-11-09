import React from "react";
import { C, Svg, Box, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Story: React.FC = () => {
  const { cue } = useScene();
  const file = cue("A Change Story says why");
  const cover = cue("Story Coverage then");
  const rows: [string, number][] = [
    ["Loader.load()  changed", cue("needs a theme")],
    ["Loader.save()  added", cue("note of its own")],
    ["Parser         moved", cue("name something real")],
  ];
  return (
    <>
      <Text x={960} y={140} size={38} font="mono" color={ROLE.reason} at={cue("Change Commits says")}>ChangeCommits: git blame → commit messages</Text>
      <Svg>
        <Box x={520} y={500} w={800} h={380} color={ROLE.story} fill={C.surface} r={16} at={file} />
        <Box x={1420} y={500} w={760} h={380} color={ROLE.diff} fill={C.surface} r={16} at={cover} />
      </Svg>
      <Text x={520} y={340} size={30} color={ROLE.story} at={file}>.gloss/changes/&lt;branch&gt;.md</Text>
      <Text x={170} y={430} size={26} font="mono" anchor="left" color={C.text} at={cue("A heading")}># Say why each change was made</Text>
      <Text x={170} y={510} size={26} font="mono" anchor="left" color={C.gold} at={cue("themes")}>## Read the why from commits</Text>
      <Text x={170} y={590} size={26} font="mono" anchor="left" color={ROLE.graph} at={cue("links to the types")}>{"``ChangeCommits``"}</Text>
      <Text x={1420} y={340} size={30} color={ROLE.diff} at={cover}>the diff's changes</Text>
      {rows.map(([text, at], i) => (
        <React.Fragment key={text}>
          <Text x={1100} y={430 + i * 90} size={28} font="mono" anchor="left" color={C.text} at={cover}>{text}</Text>
          <Text x={1700} y={430 + i * 90} size={36} color={ROLE.graph} at={at}>✓</Text>
        </React.Fragment>
      ))}
      <Text x={960} y={860} size={36} color={C.text} at={cue("written down")}>the reason is written down, and checked</Text>
    </>
  );
};
