import { editAnchor, editChanges, needsApproval } from "./edit-changes";
import type { TimelinePeriod } from "./field-timeline";

// LU 29's sector (owner 2026-11-16): 2024–2025 holds 4500 from survey, Live is
// empty from nlr. Editing from Live and ticking 2024–2025 too, the form keeps
// Live's empty value; Save would write it over 4500, so the timeline shows that
// change and Save waits for the user's approval.
const period = (
  valid_from: string,
  valid_to: string,
  values: Record<string, unknown>,
  data_source_id: number | null
): TimelinePeriod => ({
  valid_from,
  valid_to,
  values,
  data_source_id,
  edit_comment: null,
  edit_by_user_id: null,
  edit_at: null,
});
const NLR = 1;
const SURVEY = 2;
const sector = [
  period("2024-01-01", "2025-12-31", { sector_id: 4500 }, SURVEY),
  period("2026-01-01", "infinity", { sector_id: null }, NLR),
];

describe("editChanges", () => {
  it("is empty when the form holds the ticked period's own values", () => {
    expect(editChanges(sector, [1], { sector_id: "" }, String(NLR))).toEqual(new Map());
  });

  it("names what the form's values replace in each ticked period", () => {
    expect(editChanges(sector, [0, 1], { sector_id: "" }, String(NLR))).toEqual(
      new Map([
        [
          0,
          {
            columns: [{ column: "sector_id", from: 4500, to: "" }],
            dataSource: { from: SURVEY, to: NLR },
          },
        ],
      ])
    );
  });

  it("changes every ticked period that does not hold the chosen value", () => {
    const changes = editChanges(sector, [0, 1], { sector_id: "6420" }, String(NLR));
    expect(changes.get(0)?.columns).toEqual([{ column: "sector_id", from: 4500, to: "6420" }]);
    expect(changes.get(1)).toEqual({
      columns: [{ column: "sector_id", from: null, to: "6420" }],
      dataSource: null,
    });
  });

  it("compares a group's columns one by one", () => {
    const contact = [
      period("2025-01-01", "2025-12-31", { email_address: "john@doe.com", web_address: "https://my.home.com" }, 5),
      period("2026-01-01", "infinity", { email_address: null, web_address: "https://my.home.com" }, 5),
    ];
    expect(
      editChanges(contact, [0, 1], { email_address: "", web_address: "https://my.home.com", fax_number: "1" }, "5")
    ).toEqual(
      new Map([
        [0, { columns: [{ column: "email_address", from: "john@doe.com", to: "" }], dataSource: null }],
      ])
    );
  });

  it("fills a ticked hole with the form's values", () => {
    const withHole = [
      { ...period("2025-01-01", "2025-12-31", { sector_id: null }, null), empty: true },
      period("2026-01-01", "infinity", { sector_id: 4500 }, NLR),
    ];
    expect(editChanges(withHole, [0, 1], { sector_id: "4500" }, String(NLR))).toEqual(
      new Map([
        [
          0,
          {
            columns: [{ column: "sector_id", from: null, to: "4500" }],
            dataSource: { from: null, to: NLR },
          },
        ],
      ])
    );
  });
});

describe("editAnchor", () => {
  // The owner's case (2026-11-16): start on Live, tick 2024, untick Live.
  it("stays on the anchor while it is ticked", () => {
    expect(editAnchor(1, [0, 1])).toBe(1);
  });

  it("moves to the nearest ticked period when the anchor is unticked", () => {
    expect(editAnchor(1, [0])).toBe(0);
    expect(editAnchor(0, [2, 3])).toBe(2);
    expect(editAnchor(3, [0, 1])).toBe(1);
  });

  it("takes the first tick as the anchor when there was none", () => {
    expect(editAnchor(-1, [2])).toBe(2);
  });

  it("has no anchor when nothing is ticked", () => {
    expect(editAnchor(1, [])).toBe(-1);
  });
});

// The form starts from the values the page shows: Live's (period 1).
const LIVE = 1;

describe("needsApproval", () => {
  it("asks when the save changes a ticked period besides the one the form shows", () => {
    expect(needsApproval(editChanges(sector, [0, 1], { sector_id: "" }, String(NLR)), LIVE)).toBe(true);
  });

  it("asks when the one ticked period is not the one the form shows", () => {
    // The 2026-11-13 case: ticking only 2025 kept Live's empty email in the form.
    expect(needsApproval(editChanges(sector, [0], { sector_id: "" }, String(NLR)), LIVE)).toBe(true);
  });

  it("does not ask for a change to the period the form shows", () => {
    expect(needsApproval(editChanges(sector, [1], { sector_id: "6420" }, String(NLR)), LIVE)).toBe(false);
  });

  it("does not ask when the other ticked periods already hold the form's values", () => {
    const same = [
      period("2024-01-01", "2025-12-31", { sector_id: 6420 }, NLR),
      period("2026-01-01", "infinity", { sector_id: null }, NLR),
    ];
    expect(needsApproval(editChanges(same, [0, 1], { sector_id: "6420" }, String(NLR)), LIVE)).toBe(false);
  });

  it("does not ask when nothing changes", () => {
    expect(needsApproval(new Map(), LIVE)).toBe(false);
  });
});
