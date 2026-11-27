import { framesNeedingConfirmation, groupTimeFrames, reconcileSelectedTimeFrame, TIME_FRAME_GROUPS, type TimeFrame } from "./time-frame";

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

describe("reconcileSelectedTimeFrame", () => {
  const live = (day: string) => frame({ ident: "live", kind: "live" as TimeFrame["kind"], name: "Live frame", valid_on: day });
  const prev = frame({ ident: "prev", name: "Previous frame" });

  // Two tabs share one stored selection (atomWithStorage). Across midnight one tab's frames say the
  // live frame is valid on yesterday, the other's on today. Each tab applies the rule to what the
  // other just stored, in turn, until the selection settles.
  const settle = (start: TimeFrame, tabs: TimeFrame[][]) => {
    let selected = start;
    const stored: (string | null)[] = [];
    for (let step = 0; step < 6; step++) {
      const frames = tabs[step % tabs.length];
      const answer = reconcileSelectedTimeFrame(selected, frames, frames[0]);
      if (answer && "select" in answer) selected = answer.select;
      stored.push(selected.valid_on);
    }
    return stored;
  };

  it("settles on the later day when two tabs hold different days of the same frame", () => {
    const stored = settle(live("2026-11-26"), [[live("2026-11-26"), prev], [live("2026-11-27"), prev]]);
    expect(stored.slice(-3)).toEqual(["2026-11-27", "2026-11-27", "2026-11-27"]);
  });

  it("takes the tab's current frame when the stored one is older", () => {
    expect(reconcileSelectedTimeFrame(live("2026-11-26"), [live("2026-11-27"), prev], null)).toEqual({ select: live("2026-11-27") });
  });

  it("keeps a newer stored day and asks for fresh frames when the tab's copy is behind", () => {
    expect(reconcileSelectedTimeFrame(live("2026-11-27"), [live("2026-11-26"), prev], null)).toEqual({ refresh: true });
  });

  it("asks nothing when the selection is the tab's current frame", () => {
    expect(reconcileSelectedTimeFrame(live("2026-11-27"), [live("2026-11-27"), prev], null)).toBeNull();
  });

  it("falls back to the default frame for a selection that no longer exists", () => {
    expect(reconcileSelectedTimeFrame(frame({ ident: "gone" }), [live("2026-11-27"), prev], live("2026-11-27"))).toEqual({
      select: live("2026-11-27"),
    });
  });

  it("selects the default frame when nothing is selected", () => {
    expect(reconcileSelectedTimeFrame(null, [live("2026-11-27")], live("2026-11-27"))).toEqual({ select: live("2026-11-27") });
  });
});
