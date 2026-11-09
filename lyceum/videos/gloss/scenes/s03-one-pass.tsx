import React from "react";
import { Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

const OUT = [
  { label: "interface export", sub: "JSON or a web page", cue: "interface export" },
  { label: "map of the package", sub: "modules, folders, types", cue: "A map" },
  { label: "why one type depends on another", sub: "", cue: "The reason" },
  { label: "what changed", sub: "against a base revision", cue: "What changed" },
] as const;

export const OnePass: React.FC = () => {
  const { cue } = useScene();
  const contract = cue("contract");
  const graph = cue("graph");
  return (
    <>
      <Node x={300} y={330} w={400} h={110} label="swift-syntax parse" sub="every file, once" color={ROLE.source} at={0} />
      <Node x={300} y={620} w={520} h={90} label="declaration contracts" color={ROLE.docs} at={contract} />
      <Node x={300} y={790} w={520} h={90} label="dependency graph of types" color={ROLE.docs} at={graph} />
      <Svg>
        <Arrow from={[300, 390]} to={[300, 570]} at={cue("one pass")} color={ROLE.source} />
        <Arrow from={[300, 665]} to={[300, 745]} at={graph} color={ROLE.docs} />
        {OUT.map((o, i) => (
          <Arrow key={o.label} from={[520, 620]} to={[1010, 230 + i * 190]} at={cue(o.cue)} bend={20} color={ROLE.output} />
        ))}
      </Svg>
      {OUT.map((o, i) => (
        <Node key={o.label} x={1400} y={230 + i * 190} w={760} h={110} label={o.label} sub={o.sub || undefined} color={ROLE.output} at={cue(o.cue)} />
      ))}
      <Text x={1400} y={960} size={34} color={ROLE.output} at={cue("what that change reaches")} reveal="fade">and what the change reaches</Text>
    </>
  );
};
