import React from "react";
import { C, Code, Pill, Text, useScene } from "#kit";
import { ROLE } from "./shared";

// Simplified: an illustrative declaration in the house style.
const CODE = `/// Adds tax to the cart's subtotal, so the total matches the receipt.
///
/// - Parameter table: The rates to apply.
/// - Returns: The amount to charge.
/// - Throws: \`TaxError\` when a rate is missing.
func total(table: TaxTable) throws -> Decimal`;

export const Shape: React.FC = () => {
  const { cue } = useScene();
  const t = {
    sum: cue("summary of one"),
    blank: cue("blank line"),
    markup: cue("markup block"),
    ret: cue("return value"),
    thr: cue("what it throws"),
    find: cue("Each finding"),
    exit: cue("exit status"),
  };
  return (
    <>
      <Text x={960} y={130} size={46} at={0}>One shape for a comment</Text>
      <Code code={CODE} x={140} y={240} size={30} at={cue("triple-slash")} cps={80}
        highlights={[
          { line: 0, at: t.sum, out: t.blank, color: ROLE.docs },
          { line: 1, at: t.blank, out: t.markup, color: ROLE.rule },
          { line: 2, at: t.markup, out: t.ret, color: ROLE.output },
          { line: 3, at: t.ret, out: t.thr, color: ROLE.output },
          { line: 4, at: t.thr, color: ROLE.output },
        ]} />
      <Pill x={140} y={560} text="summary: what, then why" color={ROLE.docs} at={t.sum} anchor="left" />
      <Pill x={620} y={560} text="blank line" color={ROLE.rule} at={t.blank} anchor="left" />
      <Pill x={860} y={560} text="parameters · returns · throws" color={ROLE.output} at={t.markup} anchor="left" />
      <Text x={140} y={720} size={34} color={C.dim} font="mono" at={t.find} reveal="fade" anchor="left">Sources/Cart.swift:12:6: error: [parameter-missing] ...</Text>
      <Text x={140} y={800} size={34} color={C.dim} font="mono" at={t.find} reveal="fade" anchor="left">(simplified finding, compiler format)</Text>
      <Text x={140} y={900} size={40} color={ROLE.wrong} at={t.exit} reveal="fade" anchor="left">any error: exit status 1 → gates continuous integration</Text>
    </>
  );
};
