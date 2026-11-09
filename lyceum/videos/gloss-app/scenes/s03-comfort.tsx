import React from "react";
import { C, Pill, Text, track, useScene } from "#kit";
import { ROLE } from "./shared";

const STEPS = ["85%", "100%", "115%", "130%", "150%", "175%", "200%"];
const SCALE = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2];

export const Comfort: React.FC = () => {
  const { frame, fps, cue } = useScene();
  const wheel = cue("mouse wheel");
  const drag = cue("right button");
  const click = cue("left button");
  const steps = cue("seven steps");
  const small = cue("a little smaller");
  const big = cue("twice as big");
  const sys = cue("The second");
  const active = frame >= sys ? 1 : frame >= big ? 6 : frame >= small ? 0 : -1;
  // The map's figure zooms toward the pointer, then pans.
  const zoom = track(frame, fps, [[0, 1], [wheel, 1.5], [drag, 1.5]], 1.2);
  const panX = track(frame, fps, [[0, 0], [drag, -90]], 1.2);
  const sizeNow = track(frame, fps, [[0, 40], [small, 34], [big, 80], [sys, 40]], 1.0);
  const box = (x: number, y: number, w: number, h: number, c: string) => (
    <div style={{ position: "absolute", left: x, top: y, width: w, height: h, border: `3px solid ${c}`, borderRadius: 10, background: `${c}18` }} />
  );
  return (
    <>
      <Text x={520} y={190} size={40} color={ROLE.map} at={0}>Map</Text>
      <div style={{ position: "absolute", left: 170, top: 250, width: 700, height: 520, overflow: "hidden", border: `3px solid ${C.faint}`, borderRadius: 14, background: C.sunken }}>
        <div style={{ position: "absolute", inset: 0, transformOrigin: "420px 200px", transform: `translateX(${panX}px) scale(${zoom})` }}>
          {box(90, 90, 150, 70, ROLE.map)}
          {box(430, 70, 150, 70, ROLE.map)}
          {box(250, 280, 150, 70, ROLE.map)}
          {box(500, 330, 150, 70, ROLE.map)}
          <svg width={700} height={520} style={{ position: "absolute", inset: 0 }}>
            <line x1={240} y1={125} x2={430} y2={105} stroke={C.dim} strokeWidth={3} />
            <line x1={165} y1={160} x2={290} y2={280} stroke={C.dim} strokeWidth={3} />
            <line x1={505} y1={140} x2={575} y2={330} stroke={C.dim} strokeWidth={3} />
          </svg>
        </div>
      </div>
      <Pill x={170} y={830} text="wheel: zoom toward the pointer" color={ROLE.map} at={wheel} anchor="left" size={28} />
      <Pill x={170} y={890} text="right-button drag: pan" color={ROLE.state} at={drag} anchor="left" size={28} />
      <Pill x={170} y={950} text="left button: click and select" color={ROLE.rule} at={click} anchor="left" size={28} />

      <Text x={1380} y={190} size={40} color={ROLE.details} at={cue("The text in the details")}>Detail text size</Text>
      {STEPS.map((s, i) => (
        <Pill key={s} x={1000 + i * 125} y={330} text={s} size={26} at={steps}
          color={i === active ? C.gold : C.dim} />
      ))}
      <Text x={1125} y={395} size={24} color={C.dim} at={sys}>the system's</Text>
      <Text x={1000} y={560} size={sizeNow} font="mono" weight={600} anchor="left" at={cue("bigger or smaller")}>public struct Cart</Text>
      <Text x={1000} y={900} size={28} color={C.dim} anchor="left" at={cue("View menu")}>Settings · View menu · list and map keep their sizes</Text>
    </>
  );
};
