import React from "react";
import { C, Arrow, Node, Pill, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Story: React.FC = () => {
  const { cue } = useScene();
  const base = cue("where the branch left");
  const miss = cue("It prints what is missing");
  const exit = cue("The exit status");
  return (
    <>
      <Text x={960} y={110} size={40} color={C.dim} at={cue("the story check")}>gloss story</Text>
      <Node x={420} y={270} w={440} h={90} label="branch" sub="its name picks the file" color={ROLE.command} at={cue("Every branch")} size={38} />
      <Svg>
        <Arrow from={[640, 270]} to={[900, 270]} at={cue("a story file")} color={ROLE.story} />
      </Svg>
      <Node x={1260} y={270} w={700} h={90} label=".gloss/changes/<branch>.md" color={ROLE.story} at={cue("a story file")} size={32} mono />

      <Node x={420} y={470} w={440} h={90} label="interface then" sub="from the merge base" color={C.dim} at={base} size={36} />
      <Node x={1000} y={470} w={440} h={90} label="interface now" color={ROLE.data} at={cue("interface now")} size={36} />
      <Text x={710} y={470} size={44} color={ROLE.warning} at={cue("compares")}>≠</Text>
      <Text x={1560} y={470} size={30} color={C.dim} anchor="left" at={cue("Every type that changed")}>every changed type</Text>
      <Text x={1560} y={515} size={30} color={C.dim} anchor="left" at={cue("a note of its own")}>needs a note of its own</Text>

      <Text x={120} y={650} size={30} font="mono" color={ROLE.warning} anchor="left" at={cue("Types not in the story")}>not in the story: ...</Text>
      <Text x={120} y={710} size={30} font="mono" color={ROLE.warning} anchor="left" at={cue("Types with no note")}>no note of its own: ...</Text>
      <Text x={120} y={770} size={30} font="mono" color={ROLE.error} anchor="left" at={cue("Links that name nothing")}>names nothing: ...</Text>
      <Text x={120} y={600} size={30} color={C.dim} anchor="left" at={miss}>what it prints</Text>

      <Pill x={1130} y={680} text="0  complete story" color={ROLE.ok} at={cue("Zero for a complete")} size={32} />
      <Pill x={1130} y={770} text="1  gaps, or no story" color={ROLE.warning} at={cue("One for gaps")} size={32} />
      <Pill x={1130} y={860} text="2  git cannot answer" color={ROLE.error} at={cue("Two when git")} size={32} />
      <Text x={1130} y={610} size={30} color={C.dim} at={exit}>exit status</Text>
    </>
  );
};
