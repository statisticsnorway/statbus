import {
  fieldTimeline,
  framesOverlapping,
  opensInTimeline,
  periodsInRange,
  selectionRange,
  frameSegments,
  foldableFrames,
  visibleSegments,
  unfoldedRuns,
  rowSelected,
  frameMarker,
  toggleSelection,
  type TimelineSourceRow,
} from "@/components/form/field-timeline";
import type { TimeFrame } from "@/lib/time-frame";

// The field timeline (timeline v1): a field's values over time, one period per
// stretch where the value did not change, oldest first. The edit picks a
// stretch of these periods; its dates are the stretch's dates.

// FRAME REVIEW AS (tax_ident 6060606060): name AS 2023-2024, ASA 2025, AS 2026-.
// The 2023 and 2024 rows differ in another column, so the name has two rows there.
const nameRows: TimelineSourceRow[] = [
  {
    valid_from: "2023-01-01",
    valid_to: "2023-12-31",
    name: "FRAME REVIEW AS",
    data_source_id: 2,
    edit_comment: null,
    edit_by_user_id: 1,
    edit_at: "2026-11-10T10:00:00Z",
  },
  {
    valid_from: "2024-01-01",
    valid_to: "2024-12-31",
    name: "FRAME REVIEW AS",
    data_source_id: 2,
    edit_comment: null,
    edit_by_user_id: 1,
    edit_at: "2026-11-10T10:00:00Z",
  },
  {
    valid_from: "2025-01-01",
    valid_to: "2025-12-31",
    name: "FRAME REVIEW ASA",
    data_source_id: 5,
    edit_comment: "renamed",
    edit_by_user_id: 4,
    edit_at: "2026-11-11T12:16:57Z",
  },
  {
    valid_from: "2026-01-01",
    valid_to: "infinity",
    name: "FRAME REVIEW AS",
    data_source_id: 2,
    edit_comment: null,
    edit_by_user_id: 1,
    edit_at: "2026-11-10T10:00:00Z",
  },
];

const frame = (
  ident: string,
  kind: TimeFrame["kind"],
  valid_from: string,
  valid_to: string,
  equals_frame_ident: string | null = null
) =>
  ({
    ident,
    kind,
    name: ident,
    valid_from,
    valid_to,
    valid_on: valid_from,
    year: null,
    equals_frame_ident,
  }) as TimeFrame;
const frames = [
  frame("live", "live", "2026-01-01", "infinity"),
  frame("prev", "relative", "2025-01-01", "2025-12-31"),
  frame("y_2025", "fixed", "2025-01-01", "2025-12-31", "prev"),
  frame("y_2024", "fixed", "2024-01-01", "2024-12-31"),
  frame("y_2023", "fixed", "2023-01-01", "2023-12-31"),
];

describe("fieldTimeline", () => {
  it("merges adjacent rows where the field's value did not change, oldest first", () => {
    const periods = fieldTimeline([...nameRows].reverse(), ["name"]);
    expect(
      periods.map((p) => [p.valid_from, p.valid_to, p.values.name])
    ).toEqual([
      ["2023-01-01", "2024-12-31", "FRAME REVIEW AS"],
      ["2025-01-01", "2025-12-31", "FRAME REVIEW ASA"],
      ["2026-01-01", "infinity", "FRAME REVIEW AS"],
    ]);
  });

  it("keeps the data source, comment and editor of the period's latest row", () => {
    const periods = fieldTimeline(nameRows, ["name"]);
    expect(periods[1]).toMatchObject({
      data_source_id: 5,
      edit_comment: "renamed",
      edit_by_user_id: 4,
    });
  });

  it("compares a field group on all its columns", () => {
    const rows: TimelineSourceRow[] = [
      {
        valid_from: "2023-01-01",
        valid_to: "2025-12-31",
        address_part1: "Safari Park 67",
        region_id: 43,
      },
      {
        valid_from: "2026-01-01",
        valid_to: "2026-05-31",
        address_part1: "Safari Park 67",
        region_id: 43,
      },
      {
        valid_from: "2026-06-01",
        valid_to: "infinity",
        address_part1: "Safari Park 67",
        region_id: 44,
      },
    ];
    expect(
      fieldTimeline(rows, ["address_part1", "region_id"]).map((p) => [
        p.valid_from,
        p.valid_to,
      ])
    ).toEqual([
      ["2023-01-01", "2026-05-31"],
      ["2026-06-01", "infinity"],
    ]);
  });

  it("does not merge across a gap where the unit did not exist", () => {
    const rows: TimelineSourceRow[] = [
      { valid_from: "2023-01-01", valid_to: "2023-12-31", name: "X" },
      { valid_from: "2025-01-01", valid_to: "infinity", name: "X" },
    ];
    expect(fieldTimeline(rows, ["name"])).toHaveLength(2);
  });
});

describe("framesOverlapping", () => {
  it("names the frames a period reaches into, a relative frame once", () => {
    const periods = fieldTimeline(nameRows, ["name"]);
    expect(
      periods.map((p) => framesOverlapping(p, frames).map((f) => f.ident))
    ).toEqual([["y_2024", "y_2023"], ["prev"], ["live"]]);
  });
});

describe("frameSegments", () => {
  it("splits the periods at frame boundaries, oldest first, marking where the value changes", () => {
    const segments = frameSegments(fieldTimeline(nameRows, ["name"]), frames);
    expect(
      segments.map((s) => [
        s.valid_from,
        s.valid_to,
        s.frame?.ident ?? null,
        s.period,
        s.first,
      ])
    ).toEqual([
      ["2023-01-01", "2023-12-31", "y_2023", 0, true],
      ["2024-01-01", "2024-12-31", "y_2024", 0, false],
      ["2025-01-01", "2025-12-31", "prev", 1, true],
      ["2026-01-01", "infinity", "live", 2, true],
    ]);
  });

  it("keeps a change inside a frame as two segments of that frame", () => {
    const rows: TimelineSourceRow[] = [
      { valid_from: "2025-01-01", valid_to: "2026-05-31", region_id: 43 },
      { valid_from: "2026-06-01", valid_to: "infinity", region_id: 44 },
    ];
    const segments = frameSegments(fieldTimeline(rows, ["region_id"]), frames);
    expect(
      segments.map((s) => [
        s.valid_from,
        s.valid_to,
        s.frame?.ident ?? null,
        s.first,
      ])
    ).toEqual([
      ["2025-01-01", "2025-12-31", "prev", true],
      ["2026-01-01", "2026-05-31", "live", false],
      ["2026-06-01", "infinity", "live", true],
    ]);
  });

  it("gives time before the oldest frame no frame", () => {
    const rows: TimelineSourceRow[] = [
      { valid_from: "2020-01-01", valid_to: "2023-12-31", name: "X" },
    ];
    const segments = frameSegments(fieldTimeline(rows, ["name"]), frames);
    expect(
      segments.map((s) => [s.valid_from, s.valid_to, s.frame?.ident ?? null])
    ).toEqual([
      ["2020-01-01", "2022-12-31", null],
      ["2023-01-01", "2023-12-31", "y_2023"],
    ]);
  });
});

describe("selectionRange", () => {
  const periods = fieldTimeline(nameRows, ["name"]);

  it("runs from the first selected period's start to the last one's end", () => {
    expect(selectionRange(periods, [1, 2])).toEqual({
      validFrom: "2025-01-01",
      validTo: "infinity",
    });
  });

  it("is one stretch: a selection with a hole covers the periods between", () => {
    expect(selectionRange(periods, [2, 0])).toEqual({
      validFrom: "2023-01-01",
      validTo: "infinity",
    });
  });

  it("is empty when nothing is selected", () => {
    expect(selectionRange(periods, [])).toBeNull();
  });
});

describe("toggleSelection", () => {
  it("ticking a period extends the stretch to it", () => {
    expect(toggleSelection([], 1)).toEqual([1]);
    expect(toggleSelection([1], 3)).toEqual([1, 2, 3]);
    expect(toggleSelection([2, 3], 0)).toEqual([0, 1, 2, 3]);
  });

  it("unticking an end shrinks the stretch, unticking inside keeps the part before", () => {
    expect(toggleSelection([1, 2, 3], 3)).toEqual([1, 2]);
    expect(toggleSelection([1, 2, 3], 1)).toEqual([2, 3]);
    expect(toggleSelection([0, 1, 2, 3], 2)).toEqual([0, 1]);
    expect(toggleSelection([2], 2)).toEqual([]);
  });
});

describe("periodsInRange", () => {
  const periods = fieldTimeline(nameRows, ["name"]);

  it("selects the periods an edit's dates cover", () => {
    // The edit opened on 2025 (the shown value's validity in Previous frame).
    expect(periodsInRange(periods, "2025-01-01", "2025-12-31")).toEqual([1]);
    expect(periodsInRange(periods, "2025-01-01", null)).toEqual([1, 2]);
  });
});

describe("opensInTimeline", () => {
  const periods = fieldTimeline(nameRows, ["name"]);
  const prev = frames[1];
  const live = frames[0];
  const y2024 = frames[3];

  it("opens the frame view when the shown value covers exactly the frame", () => {
    // Owner 17:31: Previous frame and ASA 2025 overlap perfectly.
    expect(opensInTimeline(periods, prev)).toBe(false);
  });

  it("opens the frame view when the shown value covers the frame and more", () => {
    // AS 2023-2024 covers Frame 2024 wholly; the edit is the frame.
    expect(opensInTimeline(periods, y2024)).toBe(false);
  });

  it("opens the timeline when the frame holds more than one value", () => {
    const rows: TimelineSourceRow[] = [
      { valid_from: "2025-01-01", valid_to: "2026-06-30", name: "A" },
      { valid_from: "2026-07-01", valid_to: "infinity", name: "B" },
    ];
    expect(opensInTimeline(fieldTimeline(rows, ["name"]), live)).toBe(true);
  });

  it("opens the frame view when the field never changed", () => {
    expect(
      opensInTimeline(fieldTimeline(nameRows.slice(0, 2), ["name"]), y2024)
    ).toBe(false);
  });
});

describe("visibleSegments", () => {
  // 2023 monthly (12 values), 2024 one, Previous one, Live 3 values.
  const rows: TimelineSourceRow[] = [
    ...Array.from({ length: 12 }, (_, m) => {
      const mm = String(m + 1).padStart(2, "0");
      const last = new Date(Date.UTC(2023, m + 1, 0))
        .toISOString()
        .slice(0, 10);
      return { valid_from: `2023-${mm}-01`, valid_to: last, name: `M${mm}` };
    }),
    { valid_from: "2024-01-01", valid_to: "2024-12-31", name: "Y2024" },
    { valid_from: "2025-01-01", valid_to: "2025-12-31", name: "PREV" },
    { valid_from: "2026-01-01", valid_to: "2026-03-31", name: "L1" },
    { valid_from: "2026-04-01", valid_to: "2026-08-31", name: "L2" },
    { valid_from: "2026-09-01", valid_to: "infinity", name: "L3" },
  ];
  const periods = fieldTimeline(rows, ["name"]);
  const segments = frameSegments(periods, frames);
  const names = (shown: ReturnType<typeof visibleSegments>) =>
    shown.map((s) =>
      s.kind === "segment"
        ? periods[s.segment.period].values.name
        : s.kind === "fold"
          ? `+${s.hidden}`
          : "-"
    );

  it("keeps a frame with few values whole and folds a crowded one to two values", () => {
    // Owner 17:42: up to three values show; more than three show two and a button.
    expect(
      names(
        visibleSegments(segments, { maxPerFrame: 3, expanded: [], keep: [] })
      )
    ).toEqual(["M01", "+10", "M12", "Y2024", "PREV", "L1", "L2", "L3"]);
  });

  it("shows every value of an expanded frame, with no line of its own to fold it again", () => {
    const shown = visibleSegments(segments, {
      maxPerFrame: 3,
      expanded: ["y_2023"],
      keep: [],
    });
    // Owner 14:45: the opened values are marked by a bracket on the right, not by a line below them.
    expect(names(shown)).toEqual([
      "M01",
      "M02",
      "M03",
      "M04",
      "M05",
      "M06",
      "M07",
      "M08",
      "M09",
      "M10",
      "M11",
      "M12",
      "Y2024",
      "PREV",
      "L1",
      "L2",
      "L3",
    ]);
  });

  it("brackets exactly the values an expanded frame would fold away", () => {
    // Folded, 2023 shows M01 and M12 with ten between; opened, the bracket spans those ten.
    expect(
      unfoldedRuns(segments, { maxPerFrame: 3, expanded: ["y_2023"], keep: [] })
    ).toEqual([{ frame: "y_2023", periods: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }]);
    // With M06 shown, folding hides two runs, so the opened frame has two brackets.
    expect(
      unfoldedRuns(segments, {
        maxPerFrame: 3,
        expanded: ["y_2023"],
        keep: [5],
      })
    ).toEqual([
      { frame: "y_2023", periods: [0, 1, 2, 3, 4] },
      { frame: "y_2023", periods: [6, 7, 8, 9, 10] },
    ]);
    // A folded frame has no bracket: its fold line stands for the hidden values.
    expect(
      unfoldedRuns(segments, { maxPerFrame: 3, expanded: [], keep: [] })
    ).toEqual([]);
  });

  it("shows the shown value as one of the two in a folded frame", () => {
    // M06 is the value the page shows (index 5): it and the newest value show.
    expect(
      names(
        visibleSegments(segments, { maxPerFrame: 3, expanded: [], keep: [5] })
      )
    ).toEqual(["+5", "M06", "+5", "M12", "Y2024", "PREV", "L1", "L2", "L3"]);
  });

  it("shows two values even when more are ticked", () => {
    const shown = visibleSegments(segments, {
      maxPerFrame: 3,
      expanded: [],
      keep: [5, 6, 7],
    });
    expect(
      shown.filter(
        (s) => s.kind === "segment" && s.segment.frame?.ident === "y_2023"
      )
    ).toHaveLength(2);
  });

  it("names the frames that can fold, for expand all and collapse all", () => {
    // Owner 17:47: one control opens or folds the whole timeline.
    expect(foldableFrames(segments, 3)).toEqual(["y_2023"]);
  });

  it("counts a fold as ticked when every value it hides is ticked", () => {
    // Owner 15:08: a selection across a folded run shows as one unbroken stretch.
    const shown = visibleSegments(segments, {
      maxPerFrame: 3,
      expanded: [],
      keep: [],
    });
    const fold = shown.find((s) => s.kind === "fold")!;
    const all = Array.from({ length: 12 }, (_, k) => k);
    expect(rowSelected(fold, all)).toBe(true);
    expect(
      rowSelected(
        fold,
        all.filter((k) => k !== 6)
      )
    ).toBe(false);
    expect(rowSelected(shown[0], [0])).toBe(true);
    expect(rowSelected(shown[0], [1])).toBe(false);
  });
});

describe("frameMarker", () => {
  const withYear = (tf: TimeFrame, year: number) =>
    ({ ...tf, year }) as TimeFrame;
  it("names the kind and its year for Live and Previous, and the year for a fixed frame", () => {
    // Owner 15:10: "Previous" above "2025", "Live" above "2026"; a fixed frame is its year.
    expect(
      frameMarker(
        withYear(frame("live", "live", "2026-01-01", "infinity"), 2026)
      )
    ).toEqual({ label: "Live", year: "2026" });
    expect(
      frameMarker(
        withYear(frame("prev", "relative", "2025-01-01", "2025-12-31"), 2025)
      )
    ).toEqual({ label: "Previous", year: "2025" });
    expect(
      frameMarker(
        withYear(frame("y_2023", "fixed", "2023-01-01", "2023-12-31"), 2023)
      )
    ).toEqual({ label: "2023", year: null });
  });
});
