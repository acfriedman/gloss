import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Layers: React.FC = () => {
  const { cue } = useScene();
  const read = cue("Gloss Read");
  const lint = cue("Gloss Lint holds");
  const model = cue("Gloss Model holds");
  const map = cue("Gloss Map arranges");
  const page = cue("Gloss Page draws");
  const app = cue("Gloss App draws");
  return (
    <>
      <Node x={960} y={900} w={560} h={90} label="GlossRead" sub="" color={ROLE.source} at={read} mono />
      <Node x={620} y={730} w={440} h={90} label="GlossLint" color={ROLE.rule} at={lint} mono />
      <Node x={1300} y={730} w={440} h={90} label="GlossModel" color={ROLE.docs} at={model} mono />
      <Node x={960} y={560} w={560} h={90} label="GlossMap" color={ROLE.output} at={map} mono />
      <Node x={620} y={390} w={440} h={90} label="GlossPage" color={ROLE.output} at={page} mono />
      <Node x={1300} y={390} w={440} h={90} label="GlossApp" color={ROLE.output} at={app} mono />
      <Svg>
        <Arrow from={[620, 685]} to={[860, 945]} at={lint} color={C.dim} />
        <Arrow from={[1300, 685]} to={[1060, 945]} at={model} color={C.dim} />
        <Arrow from={[860, 515]} to={[620, 685]} at={map} color={C.dim} />
        <Arrow from={[1060, 515]} to={[1300, 685]} at={map} color={C.dim} />
        <Arrow from={[620, 345]} to={[860, 515]} at={page} color={C.dim} />
        <Arrow from={[1300, 345]} to={[1060, 515]} at={app} color={C.dim} />
      </Svg>
      <Text x={960} y={130} size={44} at={0} reveal="fade">each layer depends only on the ones below it</Text>
      <Text x={960} y={250} size={36} color={ROLE.wrong} at={cue("never read from each other")} reveal="fade">Lint and Model never read from each other</Text>
      <Text x={960} y={990} size={36} color={ROLE.output} at={cue("can't disagree")} reveal="fade">page and app draw from the same map</Text>
    </>
  );
};
