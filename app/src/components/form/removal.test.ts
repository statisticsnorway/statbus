import { piecesInPeriod, removalCaption, removalPatch, removalRuns, removalSummary } from "./removal";
import type { TimelinePeriod } from "./field-timeline";

// Remove mode ticks pieces of the timeline, one per frame; each unbroken run of
// ticked pieces is one stretch to remove (owner 2026-11-13: gaps are allowed).
const pieces = [
  { valid_from: "2024-01-01", valid_to: "2024-12-31" },
  { valid_from: "2025-01-01", valid_to: "2025-12-31" },
  { valid_from: "2026-01-01", valid_to: "infinity" },
];

describe("removalRuns", () => {
  it("joins neighbouring ticked pieces into one stretch", () => {
    expect(removalRuns(pieces, [0, 1])).toEqual([{ validFrom: "2024-01-01", validTo: "2025-12-31" }]);
  });

  it("keeps a gap: each unbroken run is its own stretch, oldest first", () => {
    expect(removalRuns(pieces, [2, 0])).toEqual([
      { validFrom: "2024-01-01", validTo: "2024-12-31" },
      { validFrom: "2026-01-01", validTo: null },
    ]);
  });

  it("splits a run where the pieces are not adjacent in time", () => {
    const apart = [
      { valid_from: "2024-01-01", valid_to: "2024-06-30" },
      { valid_from: "2025-01-01", valid_to: "2025-12-31" },
    ];
    expect(removalRuns(apart, [0, 1])).toEqual([
      { validFrom: "2024-01-01", validTo: "2024-06-30" },
      { validFrom: "2025-01-01", validTo: "2025-12-31" },
    ]);
  });

  it("is empty when nothing is ticked", () => {
    expect(removalRuns(pieces, [])).toEqual([]);
  });
});

const period = (valid_from: string, valid_to: string, address: string): TimelinePeriod => ({
  valid_from,
  valid_to,
  values: { address_part1: address },
  data_source_id: null,
  edit_comment: null,
  edit_by_user_id: null,
  edit_at: null,
});

// LU 29's postal location: PO Box 100 in 2024 and 2025, PO Box 200 from 2026 on.
const postal = [period("2024-01-01", "2025-12-31", "PO Box 100"), period("2026-01-01", "infinity", "PO Box 200")];

describe("removalSummary", () => {
  it("removes the part of a period inside the range and keeps both sides", () => {
    expect(removalSummary(postal, "2025-01-01", "2025-12-31")).toEqual({
      removed: [{ valid_from: "2025-01-01", valid_to: "2025-12-31", values: { address_part1: "PO Box 100" } }],
      kept: [
        { valid_from: "2024-01-01", valid_to: "2024-12-31", values: { address_part1: "PO Box 100" } },
        { valid_from: "2026-01-01", valid_to: "infinity", values: { address_part1: "PO Box 200" } },
      ],
    });
  });

  it("cuts an open-ended period inside it, keeping its start and its future", () => {
    expect(removalSummary(postal, "2026-03-01", "2026-05-31")).toEqual({
      removed: [{ valid_from: "2026-03-01", valid_to: "2026-05-31", values: { address_part1: "PO Box 200" } }],
      kept: [
        { valid_from: "2024-01-01", valid_to: "2025-12-31", values: { address_part1: "PO Box 100" } },
        { valid_from: "2026-01-01", valid_to: "2026-02-28", values: { address_part1: "PO Box 200" } },
        { valid_from: "2026-06-01", valid_to: "infinity", values: { address_part1: "PO Box 200" } },
      ],
    });
  });

  it("removes across periods, each value named for its own part", () => {
    expect(removalSummary(postal, "2025-07-01", null).removed).toEqual([
      { valid_from: "2025-07-01", valid_to: "2025-12-31", values: { address_part1: "PO Box 100" } },
      { valid_from: "2026-01-01", valid_to: "infinity", values: { address_part1: "PO Box 200" } },
    ]);
  });

  it("removes the whole record when the range covers it: nothing is kept", () => {
    expect(removalSummary(postal, "2024-01-01", null).kept).toEqual([]);
  });

  it("removes nothing where the record has no value", () => {
    expect(removalSummary([period("2026-01-01", "infinity", "PO Box 200")], "2024-01-01", "2025-12-31")).toEqual({
      removed: [],
      kept: [{ valid_from: "2026-01-01", valid_to: "infinity", values: { address_part1: "PO Box 200" } }],
    });
  });
});

// sql_saga 1.5's delete protocol on the for_portion_of view (STATBUS-611):
// PATCH ?id=eq.N {"id": null, "valid_from": S, "valid_until": E}, with E
// exclusive; a run's validTo is inclusive and null when open-ended.
describe("removalPatch", () => {
  it("ends the removal the day after a closed run's last day", () => {
    expect(removalPatch({ validFrom: "2024-01-01", validTo: "2024-12-31" })).toEqual({
      id: null,
      valid_from: "2024-01-01",
      valid_until: "2025-01-01",
    });
  });

  it("removes an open-ended run up to infinity", () => {
    expect(removalPatch({ validFrom: "2026-01-01", validTo: null })).toEqual({
      id: null,
      valid_from: "2026-01-01",
      valid_until: "infinity",
    });
  });
});

// Remove mode's Timeline starts from the Frame view's choice (owner 2026-11-13):
// the frame or dates chosen there tick the pieces inside them.
const framePieces = [
  { valid_from: "2024-01-01", valid_to: "2024-12-31" },
  { valid_from: "2025-01-01", valid_to: "2025-12-31" },
  { valid_from: "2026-01-01", valid_to: "infinity" },
];

describe("piecesInPeriod", () => {
  it("ticks the pieces inside a frame's period", () => {
    expect(piecesInPeriod(framePieces, "2025-01-01", "2025-12-31")).toEqual([1]);
    expect(piecesInPeriod(framePieces, "2026-01-01", null)).toEqual([2]);
  });

  it("ticks every piece inside dates spanning several frames", () => {
    expect(piecesInPeriod(framePieces, "2024-01-01", "2025-12-31")).toEqual([0, 1]);
  });

  it("leaves a piece the dates cut through unticked", () => {
    expect(piecesInPeriod(framePieces, "2025-06-01", null)).toEqual([2]);
  });
});

// The red button and the dialog title name what goes, then where from (owner
// 2026-11-13: "Remove Live frame (2026)" read as removing the frame itself).
describe("removalCaption", () => {
  it("removes the record from a chosen frame", () => {
    expect(
      removalCaption({ record: "contact", frameName: "Live frame (2026)", runs: [{ validFrom: "2026-01-01", validTo: null }], all: false })
    ).toEqual({ action: "Remove contact", scope: "from Live frame (2026)" });
  });

  it("removes the record for one stretch of dates", () => {
    expect(
      removalCaption({ record: "postal location", runs: [{ validFrom: "2025-01-01", validTo: "2025-12-31" }], all: false })
    ).toEqual({ action: "Remove postal location", scope: "for 2025-01-01 – 2025-12-31" });
  });

  it("counts the periods when the ticks leave a gap", () => {
    expect(
      removalCaption({
        record: "employees",
        runs: [
          { validFrom: "2024-01-01", validTo: "2024-12-31" },
          { validFrom: "2026-01-01", validTo: null },
        ],
        all: false,
      })
    ).toEqual({ action: "Remove employees", scope: "for 2 periods" });
  });

  it("says entirely when nothing stays", () => {
    expect(
      removalCaption({ record: "contact", frameName: "Live frame (2026)", runs: [{ validFrom: "2024-01-01", validTo: null }], all: true })
    ).toEqual({ action: "Remove contact", scope: "entirely" });
  });

  it("has no scope while nothing is chosen", () => {
    expect(removalCaption({ record: "contact", runs: [], all: false })).toEqual({ action: "Remove contact", scope: null });
  });
});
