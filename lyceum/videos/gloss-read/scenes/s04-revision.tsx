import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Revision: React.FC = () => {
  const { cue } = useScene();
  const commit = cue("at any commit");
  const git = cue("straight from git");
  const out = cue("checking anything");
  const idx = cue("git's index");
  const hook = cue("pre-commit hook");
  const like = cue("compares like with like");
  const one = cue("One reading");
  return (
    <>
      <Text x={960} y={150} size={40} color={C.dim} at={cue("Sometimes the question")}>an older version</Text>
      <Node x={960} y={330} w={440} h={110} label="git repository" color={ROLE.git} at={git} size={38} />
      <Svg>
        <Arrow from={[800, 390]} to={[480, 580]} at={commit} color={ROLE.git} />
        <Arrow from={[960, 390]} to={[960, 580]} at={commit} color={ROLE.git} />
        <Arrow from={[1120, 390]} to={[1440, 580]} at={idx} color={ROLE.git} />
        <Arrow from={[620, 660]} to={[820, 660]} at={like} color={ROLE.read} head />
        <Arrow from={[1100, 660]} to={[1300, 660]} at={like} color={ROLE.read} head />
      </Svg>
      <Node x={480} y={660} w={280} h={110} label="a commit" sub="a branch or a tag" color={ROLE.read} at={commit} size={36} />
      <Node x={960} y={660} w={280} h={110} label="HEAD" sub="the current commit" color={ROLE.read} at={commit} size={36} />
      <Node x={1440} y={660} w={280} h={110} label="git's index" sub="next commit" color={ROLE.read} at={idx} size={36} />
      <Text x={990} y={470} size={28} anchor="left" color={C.dim} at={out}>no checkout</Text>
      <Text x={1440} y={800} size={28} color={C.dim} at={hook}>a pre-commit hook judges the commit</Text>
      <Text x={960} y={900} size={36} color={ROLE.read} at={one}>one reading, for every other module</Text>
    </>
  );
};
