import React from "react";
import { C, Arrow, Node, Svg, Text, useScene } from "#kit";
import { ROLE } from "./shared";

export const Graph: React.FC = () => {
  const { cue } = useScene();
  const nodes = cue("From those mentions");
  const edges = cue("An edge says");
  const prop = cue("in a property");
  const param = cue("in a parameter");
  const reason = cue("Reason says why");
  return (
    <>
      <Svg>
        <Arrow from={[860, 285]} to={[640, 445]} at={edges} color={ROLE.graph} />
        <Arrow from={[1060, 285]} to={[1280, 445]} at={edges} color={ROLE.graph} />
        <Arrow from={[1210, 500]} to={[710, 500]} at={edges} color={ROLE.graph} />
        <Arrow from={[560, 555]} to={[560, 705]} at={reason} color={ROLE.reason} />
      </Svg>
      <Node x={960} y={230} w={300} h={100} label="Interface" color={ROLE.contract} at={nodes} size={40} />
      <Node x={560} y={500} w={300} h={100} label="Contract" color={ROLE.contract} at={nodes} size={40} />
      <Node x={1360} y={500} w={300} h={100} label="Graph" color={ROLE.graph} at={nodes} size={40} />
      <Node x={560} y={760} w={300} h={100} label="Reason" color={ROLE.reason} at={reason} size={40} />
      <Text x={690} y={350} size={26} font="mono" color={C.dim} at={prop}>property</Text>
      <Text x={1230} y={350} size={26} font="mono" color={C.dim} at={prop}>property</Text>
      <Text x={960} y={465} size={26} font="mono" color={C.dim} at={param}>parameter</Text>
      <Text x={600} y={632} size={26} font="mono" anchor="left" color={C.dim} at={cue("in a return")}>returns</Text>
      <Text x={1000} y={760} size={30} font="mono" anchor="left" color={ROLE.reason} at={reason}>Contract.reason(toward:) → Reason</Text>
      <Text x={1360} y={650} size={30} color={C.dim} at={cue("throws clause")}>also: throws · conformance</Text>
      <Text x={1360} y={900} size={30} color={C.faint} at={cue("body mentions")}>body only: implementation, not interface</Text>
    </>
  );
};
