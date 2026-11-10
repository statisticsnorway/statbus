import { defaultEditRange } from "@/components/form/edit-range";

// STATBUS-604: an edit defaults to the stretch where the value shown is valid,
// bounded by the selected time frame, so it changes exactly what the user saw.
describe("defaultEditRange", () => {
  const year2026 = { valid_from: "2026-01-01", valid_to: "2026-12-31" };

  it("starts where the unit begins when it was born inside the selected year", () => {
    // Norway: the unit exists from 2026-11-07; the user works on 2026.
    expect(
      defaultEditRange(
        [{ valid_from: "2026-11-07", valid_to: "infinity", value: "0001 INVEST AS" }],
        "0001 INVEST AS",
        year2026
      )
    ).toEqual({ validFrom: "2026-11-07", validTo: "2026-12-31" });
  });

  it("covers the whole stretch of the value, across rows split by another column", () => {
    // Name B from March, sector changes in June: B spans two rows.
    expect(
      defaultEditRange(
        [
          { valid_from: "2020-01-01", valid_to: "2026-02-28", value: "A" },
          { valid_from: "2026-03-01", valid_to: "2026-05-31", value: "B" },
          { valid_from: "2026-06-01", valid_to: "infinity", value: "B" },
        ],
        "B",
        year2026
      )
    ).toEqual({ validFrom: "2026-03-01", validTo: "2026-12-31" });
  });

  it("stops where the value changes, so an earlier different value is left alone", () => {
    expect(
      defaultEditRange(
        [
          { valid_from: "2020-01-01", valid_to: "2026-05-31", value: "A" },
          { valid_from: "2026-06-01", valid_to: "infinity", value: "B" },
        ],
        "A",
        year2026
      )
    ).toEqual({ validFrom: "2026-01-01", validTo: "2026-05-31" });
  });

  it("keeps infinity open when the selected context is open-ended", () => {
    expect(
      defaultEditRange(
        [{ valid_from: "2013-01-01", valid_to: "infinity", value: "X" }],
        "X",
        { valid_from: "2026-01-01", valid_to: "infinity" }
      )
    ).toEqual({ validFrom: "2026-01-01", validTo: "infinity" });
  });

  it("falls back to the selected context when no row shows the value", () => {
    expect(defaultEditRange([], "X", year2026)).toEqual({
      validFrom: "2026-01-01",
      validTo: "2026-12-31",
    });
  });
});
