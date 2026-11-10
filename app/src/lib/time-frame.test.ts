import { framesNeedingConfirmation, groupTimeFrames, TIME_FRAME_GROUPS, type TimeFrame } from "./time-frame";

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

  it("gives each group the explanation of its kind for the info icon", () => {
    const groups = groupTimeFrames(frames, { forMenu: false });
    expect(groups.map((g) => [g.kind, g.explanation])).toEqual(
      TIME_FRAME_GROUPS.map((g) => [g.kind, g.explanation])
    );
  });
});

describe("framesNeedingConfirmation", () => {
  const dated: TimeFrame[] = [
    frame({ ident: "live", kind: "live", name: "Live frame (2026)", valid_from: "2026-01-01", valid_to: "infinity" }),
    frame({ ident: "prev", kind: "relative", name: "Previous frame (2025)", valid_from: "2025-01-01", valid_to: "2025-12-31" }),
    frame({ ident: "y_2025", kind: "fixed", name: "Frame 2025", valid_from: "2025-01-01", valid_to: "2025-12-31", equals_frame_ident: "prev" }),
    frame({ ident: "y_2024", kind: "fixed", name: "Frame 2024", valid_from: "2024-01-01", valid_to: "2024-12-31" }),
  ];
  const names = (fs: TimeFrame[]) => fs.map((f) => f.name);

  it("asks nothing for a change inside the live frame", () => {
    expect(names(framesNeedingConfirmation(dated, "2026-01-01", null))).toEqual([]);
    expect(names(framesNeedingConfirmation(dated, "2026-03-01", "2026-06-30"))).toEqual([]);
  });

  it("names the previous frame once, not also Frame 2025, for a change in last year", () => {
    expect(names(framesNeedingConfirmation(dated, "2025-01-01", "2025-12-31"))).toEqual(["Previous frame (2025)"]);
  });

  it("names every past frame an open-ended change from 2024 reaches into", () => {
    expect(names(framesNeedingConfirmation(dated, "2024-07-01", null))).toEqual(["Previous frame (2025)", "Frame 2024"]);
  });

  it("asks nothing when the change has no start yet", () => {
    expect(framesNeedingConfirmation(dated, null, null)).toEqual([]);
  });
});
