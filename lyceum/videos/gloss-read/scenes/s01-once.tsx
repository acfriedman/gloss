import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Once: React.FC = () => {
  const { cue } = useScene();
  const lint = cue("The lint checks");
  const model = cue("The model reads");
  const disagree = cue("they could disagree");
  const one = cue("one Reading");
  const bottom = cue("bottom of the package");
  const lib = cue("swift syntax library");
  return (
    <>
      <Text x={960} y={150} size={40} color={C.dim} at={cue("Two modules")}>what the doc comments say</Text>
      <Svg>
        <Arrow from={[560, 400]} to={[860, 640]} at={one} color={ROLE.read} />
        <Arrow from={[1360, 400]} to={[1060, 640]} at={one} color={ROLE.read} />
        <Arrow from={[960, 780]} to={[960, 880]} at={lib} color={C.dim} />
      </Svg>
      <Node x={560} y={340} w={420} h={120} label="Gloss Lint" sub="house style" color={ROLE.lint} at={lint} size={42} />
      <Node x={1360} y={340} w={420} h={120} label="Gloss Model" sub="contracts" color={ROLE.model} at={model} size={42} />
      <Text x={960} y={340} size={44} color={ROLE.wrong} at={disagree}>≠</Text>
      <Node x={960} y={700} w={520} h={140} label="Gloss Read" sub="Reading" color={ROLE.read} at={one} size={46} />
      <Text x={1330} y={700} size={30} color={C.dim} anchor="left" at={bottom}>bottom of the package</Text>
      <Text x={960} y={940} size={32} font="mono" color={C.dim} at={lib}>swift-syntax</Text>
    </>
  );
};
