import { capToExistence, unitExistence } from "@/components/form/unit-existence";

// A record that belongs to a unit (a contact, location, activity, statistic) can
// only be valid where the unit exists; the temporal foreign key enforces it. The
// unit's history is often split into many rows (every change of any column splits
// it), so where it exists is the union of its rows, not any one row. An edit of
// the record is capped to that existence: it starts no earlier than the unit and
// ends no later.
const row = (valid_from: string, valid_until: string) => ({ valid_from, valid_until });

describe("unitExistence", () => {
  it("joins rows that follow each other into one span", () => {
    expect(
      unitExistence([
        row("2026-07-01", "infinity"),
        row("2024-01-01", "2025-01-01"),
        row("2025-01-01", "2026-01-01"),
        row("2026-01-01", "2026-07-01"),
      ])
    ).toEqual([{ validFrom: "2024-01-01", validTo: "infinity" }]);
  });

  it("keeps a gap where the unit did not exist", () => {
    expect(unitExistence([row("2020-01-01", "2021-01-01"), row("2023-01-01", "infinity")])).toEqual([
      { validFrom: "2020-01-01", validTo: "2020-12-31" },
      { validFrom: "2023-01-01", validTo: "infinity" },
    ]);
  });
});

describe("capToExistence", () => {
  const existence = [{ validFrom: "2024-03-15", validTo: "infinity" }];

  it("leaves an edit inside the unit's existence as it is", () => {
    expect(capToExistence(existence, "2026-01-01", "infinity")).toEqual({ validFrom: "2026-01-01", validTo: "infinity" });
  });

  it("starts an edit that reaches back before the unit where the unit starts", () => {
    expect(capToExistence(existence, "2024-01-01", "2024-12-31")).toEqual({ validFrom: "2024-03-15", validTo: "2024-12-31" });
  });

  it("ends an edit where the unit ends", () => {
    expect(capToExistence([{ validFrom: "2020-01-01", validTo: "2025-06-30" }], "2025-01-01", "infinity")).toEqual({
      validFrom: "2025-01-01",
      validTo: "2025-06-30",
    });
  });

  it("finds nothing when the unit does not exist in the edit's period", () => {
    expect(capToExistence(existence, "2022-01-01", "2022-12-31")).toBeNull();
  });
});
