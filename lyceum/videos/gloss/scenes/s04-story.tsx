import React from "react";
import { C, Code, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified from the README's example change story.
const CODE = `# Totals include tax

Carts showed totals before tax,
so checkout disagreed with the receipt.

## Tax

\`\`Cart/total()\`\` now adds tax from
\`\`TaxTable\`\`.

### \`\`Cart\`\`

\`total()\` keeps its signature;
only the amount changes.`;

export const Story: React.FC = () => {
  const { cue } = useScene();
  const theme = cue("Themes");
  const note = cue("A note");
  const check = cue("checks it");
  return (
    <>
      <Text x={140} y={120} size={34} color={C.dim} font="mono" at={cue("change story")} anchor="left" reveal="fade">{".gloss/changes/<branch>.md"}</Text>
      <Code code={CODE} x={140} y={190} size={32} at={cue("A branch")} cps={60}
        highlights={[
          { line: 0, at: cue("headline"), out: theme, color: ROLE.docs },
          { line: 5, at: theme, out: note, color: ROLE.rule },
          { line: 7, at: theme, out: note, color: ROLE.rule },
          { line: 9, at: note, color: ROLE.output },
        ]} />
      <Text x={1000} y={300} size={36} color={ROLE.rule} anchor="left" at={theme} reveal="fade">theme: links the types it is about</Text>
      <Text x={1000} y={380} size={36} color={ROLE.output} anchor="left" at={note} reveal="fade">note: one type's side of the change</Text>
      <Text x={1000} y={600} size={36} color={C.text} font="mono" anchor="left" at={check} reveal="fade">$ gloss story</Text>
      <Text x={1000} y={680} size={32} color={ROLE.wrong} anchor="left" at={cue("It fails")} reveal="fade">fails while a changed type has no theme,</Text>
      <Text x={1000} y={730} size={32} color={ROLE.wrong} anchor="left" at={cue("no note")} reveal="fade">no note, or a link names nothing</Text>
      <Text x={1000} y={850} size={40} color={ROLE.output} anchor="left" at={cue("land unexplained")} reveal="fade">no change lands unexplained</Text>
    </>
  );
};
