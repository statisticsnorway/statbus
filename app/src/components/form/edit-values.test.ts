import { editStartValues } from "./edit-values";
import type { TimelinePeriod } from "./field-timeline";

// The values an edit starts from are the ticked stretch's own (owner 2026-11-13):
// ticking 2025 of EDIT PAGES SPLIT's Communication and typing a fax kept Live's empty
// email in the form, and Save wrote it over 2025's email john@doe.com.
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
const periods = [
  period(
    "2024-01-01",
    "2024-12-31",
    { email_address: null, web_address: "https://my.home.com" },
    null
  ),
  period(
    "2025-01-01",
    "2025-12-31",
    { email_address: "john@doe.com", web_address: "https://my.home.com" },
    5
  ),
  period(
    "2026-01-01",
    "infinity",
    { email_address: null, web_address: "https://my.home.com" },
    null
  ),
];

describe("editStartValues", () => {
  it("starts from the one ticked period's values and data source", () => {
    expect(editStartValues(periods, [1])).toEqual({
      values: {
        email_address: "john@doe.com",
        web_address: "https://my.home.com",
      },
      dataSourceId: 5,
      differing: [],
    });
  });

  it("names the columns that differ and starts them from the newest ticked period", () => {
    expect(editStartValues(periods, [1, 2])).toEqual({
      values: { email_address: null, web_address: "https://my.home.com" },
      dataSourceId: null,
      differing: ["email_address"],
    });
  });

  it("has nothing to start from when nothing is ticked", () => {
    expect(editStartValues(periods, [])).toBeNull();
  });

  it("fills a hole with the ticked periods' value, and a hole is no difference", () => {
    const withHole = [
      periods[0],
      { ...period("2025-01-01", "2025-12-31", { email_address: null, web_address: null }, null), empty: true },
      periods[2],
    ];
    expect(editStartValues(withHole, [0, 1, 2])).toEqual({
      values: { email_address: null, web_address: "https://my.home.com" },
      dataSourceId: null,
      differing: [],
    });
  });
});
