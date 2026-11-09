import React from "react";
import { C, Code, Fade, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: an illustrative doc comment, not from the sources.
const CODE = `/// gets the total
/// might include tax
/// (old: before tax)
func total() -> Decimal`;

export const Hook: React.FC = () => {
  const { cue } = useScene();
  const drift = cue("They drift.");
  const bet = cue("simple bet");
  const same = cue("same shape");
  return (
    <>
      <Text x={960} y={170} size={52} at={0} dur={1}>Doc comments</Text>
      <Code code={CODE} x={560} y={330} size={44} at={cue("sits right beside")} cps={30}
        strike={[{ lines: [2], at: drift }]}
        highlights={[{ line: 2, at: drift, color: ROLE.wrong }]} />
      <Fade at={cue("nobody")} x={1500} y={440}>
        <Text x={0} y={0} size={200} color={C.faint} anchor="center">?</Text>
      </Fade>
      <Text x={960} y={720} size={40} color={ROLE.wrong} at={cue("no shape")} reveal="fade">no shape: every one is different</Text>
      <Text x={960} y={860} size={46} color={ROLE.docs} at={bet} reveal="fade">one shape, so the docs can be checked</Text>
      <Text x={960} y={950} size={46} color={ROLE.output} at={cue("interface", { after: same })} reveal="fade">and read as the interface they describe</Text>
    </>
  );
};
