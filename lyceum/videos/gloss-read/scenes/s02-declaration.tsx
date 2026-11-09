import React from "react";
import { C, Code, Node, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: a declaration with a doc comment, as an example of what is read.
const CODE = [
  "/// Adds a line item to the cart.",
  "///",
  "/// - Parameter item: The item to add.",
  "/// - Returns: The updated total.",
  "func add(_ item: Item) -> Total",
].join("\n");

export const Declaration: React.FC = () => {
  const { cue } = useScene();
  const entry = cue("entry with three parts");
  const first = cue("The first is");
  const second = cue("The second is");
  const third = cue("The third is");
  const roles = ["property", "parameter", "returns", "throws", "conformance", "body"];
  const rolesAt = cue("Each mention says where");
  return (
    <>
      <Text x={960} y={130} size={36} color={C.dim} at={cue("A Reading is made")}>one declaration, simplified</Text>
      <Code code={CODE} x={80} y={250} size={28} at={cue("made of declarations")} cps={60}
        highlights={[
          { line: 4, at: first, color: C.text },
          { line: 0, to: 34, at: second, color: ROLE.doc },
          { line: 2, at: cue("callouts"), color: C.gold },
          { line: 3, at: cue("callouts"), color: C.gold },
          { line: 4, from: 12, to: 16, at: cue("type names it mentions"), color: ROLE.read },
        ]} />
      <Text x={1380} y={180} size={44} color={ROLE.read} at={entry}>Entry</Text>
      <Node x={1380} y={290} w={480} h={90} label="declaration" sub="kind, name, parameters" color={C.text} at={first} size={34} />
      <Node x={1380} y={420} w={480} h={90} label="doc" sub="lines, summary, callouts, notes" color={ROLE.doc} at={second} size={34} />
      <Node x={1380} y={550} w={480} h={90} label="details" sub="access, header, mentions" color={ROLE.read} at={third} size={34} />
      <Text x={640} y={680} size={30} color={C.dim} at={rolesAt}>where a mention sits</Text>
      {roles.map((r, i) => (
        <Pill key={r} x={240 + (i % 3) * 330} y={760 + Math.floor(i / 3) * 90} text={r} color={r === "body" ? C.dim : ROLE.read}
          at={cue(["in a property", "a parameter", "a return", "a throws clause", "an inheritance clause", "only in a body"][i], { after: rolesAt })} size={30} />
      ))}
    </>
  );
};
