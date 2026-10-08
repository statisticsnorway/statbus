import {
  exportBaseName,
  parseUnitTypeFilter,
  EXCEL_CONFIRM_ROWS,
  EXCEL_MAX_DATA_ROWS,
} from "./export-query";

describe("parseUnitTypeFilter", () => {
  it("unwraps the PostgREST in.(...) filter form", () => {
    expect(parseUnitTypeFilter("in.(establishment)")).toEqual({
      unitType: "establishment",
      hasSingleUnitType: true,
      isEstablishment: true,
    });
  });

  it("treats multiple unit types as not-single", () => {
    expect(parseUnitTypeFilter("in.(legal_unit,establishment)")).toEqual({
      unitType: "legal_unit,establishment",
      hasSingleUnitType: false,
      isEstablishment: false,
    });
  });

  it("treats a missing filter as all unit types", () => {
    expect(parseUnitTypeFilter(null)).toEqual({
      unitType: "",
      hasSingleUnitType: false,
      isEstablishment: false,
    });
  });
});

describe("exportBaseName", () => {
  it("pluralizes a single unit type", () => {
    expect(exportBaseName("in.(establishment)")).toBe("establishments");
  });

  it("falls back to statistical_units for mixed exports", () => {
    expect(exportBaseName(null)).toBe("statistical_units");
    expect(exportBaseName("in.(legal_unit,establishment)")).toBe(
      "statistical_units"
    );
  });
});

describe("xlsx bounds", () => {
  it("keeps the hard cap at the xlsx format limit minus the header row", () => {
    expect(EXCEL_MAX_DATA_ROWS).toBe(1_048_575);
  });

  it("requires confirmation above ~100k rows", () => {
    expect(EXCEL_CONFIRM_ROWS).toBe(100_000);
  });
});
