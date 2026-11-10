import { groupTimeFrames, type TimeFrame } from "./time-frame";

const frame = (overrides: Partial<TimeFrame>): TimeFrame => ({
  ident: null,
  kind: null,
  name: null,
  valid_from: null,
  valid_to: null,
  valid_on: null,
  year: null,
  equals_frame_ident: null,
  ...overrides,
});

// public.time_frame on 2026-11-10 with data in 2024 and 2022.
const frames: TimeFrame[] = [
  frame({ ident: "live", kind: "live", name: "Live frame (2026)" }),
  frame({ ident: "prev", kind: "relative", name: "Previous frame (2025)" }),
  frame({ ident: "y_2025", kind: "fixed", name: "Frame 2025", equals_frame_ident: "prev" }),
  frame({ ident: "y_2024", kind: "fixed", name: "Frame 2024" }),
  frame({ ident: "y_2022", kind: "fixed", name: "Frame 2022" }),
];

const shape = (groups: ReturnType<typeof groupTimeFrames>) =>
  groups.map((g) => [g.heading, g.frames.map((f) => f.name)]);

describe("groupTimeFrames", () => {
  it("lists the menu's frames under their kind, leaving out a fixed frame that equals a relative one", () => {
    expect(shape(groupTimeFrames(frames, { forMenu: true }))).toEqual([
      ["Live frame", ["Live frame (2026)"]],
      ["Relative frames", ["Previous frame (2025)"]],
      ["Fixed frames", ["Frame 2024", "Frame 2022"]],
    ]);
  });

  it("lists every frame for an import page", () => {
    expect(shape(groupTimeFrames(frames, { forMenu: false }))).toEqual([
      ["Live frame", ["Live frame (2026)"]],
      ["Relative frames", ["Previous frame (2025)"]],
      ["Fixed frames", ["Frame 2025", "Frame 2024", "Frame 2022"]],
    ]);
  });
});
