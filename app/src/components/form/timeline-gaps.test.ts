import { withGaps } from "./timeline-gaps";
import type { TimelinePeriod } from "./field-timeline";

// A hole in a record's history (owner 2026-11-13: EDIT PAGES SPLIT's Communication has 2024 and 2026-, nothing in
// 2025) is drawn as a period of its own, so the Timeline shows it and ticking around it makes filling it visible.
// Only where the unit exists: before the unit was born or after it ended there is no hole, only nothing.
const period = (
  valid_from: string,
  valid_to: string,
  email: string | null
): TimelinePeriod => ({
  valid_from,
  valid_to,
  values: { email_address: email, web_address: "https://my.home.com" },
  data_source_id: null,
  edit_comment: null,
  edit_by_user_id: null,
  edit_at: null,
});
const hole = (valid_from: string, valid_to: string) => ({
  valid_from,
  valid_to,
  values: { email_address: null, web_address: null },
  data_source_id: null,
  edit_comment: null,
  edit_by_user_id: null,
  edit_at: null,
  empty: true,
});

describe("withGaps", () => {
  const split = [
    period("2024-01-01", "2024-12-31", null),
    period("2026-01-01", "infinity", null),
  ];

  it("draws the hole between two periods where the unit exists", () => {
    expect(
      withGaps(split, [{ validFrom: "2024-01-01", validTo: "infinity" }])
    ).toEqual([split[0], hole("2025-01-01", "2025-12-31"), split[1]]);
  });

  it("draws no hole where the unit did not exist", () => {
    expect(
      withGaps(split, [
        { validFrom: "2024-01-01", validTo: "2024-12-31" },
        { validFrom: "2026-01-01", validTo: "infinity" },
      ])
    ).toEqual(split);
  });

  it("draws the unit's time before the first value and after the last as holes too", () => {
    expect(
      withGaps(
        [period("2025-01-01", "2025-12-31", "a@b.c")],
        [{ validFrom: "2024-06-01", validTo: "infinity" }]
      )
    ).toEqual([
      hole("2024-06-01", "2024-12-31"),
      period("2025-01-01", "2025-12-31", "a@b.c"),
      hole("2026-01-01", "infinity"),
    ]);
  });

  it("leaves the periods as they are while the unit's existence is unknown", () => {
    expect(withGaps(split, undefined)).toEqual(split);
  });
});
