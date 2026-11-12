import { removalSummary } from "./removal";
import type { TimelinePeriod } from "./field-timeline";

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
