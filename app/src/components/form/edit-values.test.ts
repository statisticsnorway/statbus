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
      differences: {},
      dataSourceRuns: [],
    });
  });

  it("names the columns that differ and starts them from the newest ticked period", () => {
    expect(editStartValues(periods, [1, 2])).toEqual({
      values: { email_address: null, web_address: "https://my.home.com" },
      dataSourceId: null,
      differing: ["email_address"],
      differences: {
        email_address: [
          { value: "john@doe.com", valid_from: "2025-01-01", valid_to: "2025-12-31" },
          { value: null, valid_from: "2026-01-01", valid_to: "infinity" },
        ],
      },
      dataSourceRuns: [
        { value: 5, valid_from: "2025-01-01", valid_to: "2025-12-31" },
        { value: null, valid_from: "2026-01-01", valid_to: "infinity" },
      ],
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
      differences: {},
      dataSourceRuns: [],
    });
  });
});

// Legal unit 29's Sector (owner 2026-11-16): 4500 in 2024 and 2025, a real row
// without a sector from 2026. An empty row is a value (none), unlike a hole.
describe("editStartValues differences", () => {
  const sector = [
    period("2024-01-01", "2024-12-31", { sector_id: 57 }, 4),
    period("2025-01-01", "2025-12-31", { sector_id: 57 }, 4),
    period("2026-01-01", "infinity", { sector_id: null }, 2),
  ];

  it("lists each differing column's values over the ticked stretch, oldest first", () => {
    const start = editStartValues(sector, [0, 1, 2]);
    expect(start?.differing).toEqual(["sector_id"]);
    expect(start?.differences).toEqual({
      sector_id: [
        { value: 57, valid_from: "2024-01-01", valid_to: "2025-12-31" },
        { value: null, valid_from: "2026-01-01", valid_to: "infinity" },
      ],
    });
  });

  it("lists the data source per stretch when the ticked periods have different ones", () => {
    expect(editStartValues(sector, [1, 2])?.dataSourceRuns).toEqual([
      { value: 4, valid_from: "2025-01-01", valid_to: "2025-12-31" },
      { value: 2, valid_from: "2026-01-01", valid_to: "infinity" },
    ]);
  });

  it("has no differences when the ticked periods agree", () => {
    const start = editStartValues(sector, [0, 1]);
    expect(start?.differences).toEqual({});
    expect(start?.dataSourceRuns).toEqual([]);
  });
});
