import {
  composeExportSearchParams,
  composeExportSelect,
  exportBaseName,
  exportFieldNames,
  exportOrder,
  parseUnitTypeFilter,
  EXCEL_CONFIRM_ROWS,
  EXCEL_MAX_DATA_ROWS,
} from "./export-query";

const baseData = {
  externalIdentTypes: [{ code: "org_no" }, { code: "tax_ident" }],
  statDefinitions: [{ code: "employees" }, { code: "turnover" }],
};

const emptyBaseData = { externalIdentTypes: [], statDefinitions: [] };

describe("exportOrder", () => {
  it("uses temporal unit identity as a deterministic order tiebreaker", () => {
    expect(exportOrder(null)).toBe(
      "name.asc,unit_type.asc,unit_id.asc,valid_from.asc,valid_to.asc"
    );
    expect(exportOrder("unit_id.desc,name.desc")).toBe(
      "unit_id.desc,name.desc,unit_type.asc,valid_from.asc,valid_to.asc"
    );
  });

  it("does not duplicate keys already present in the chosen order", () => {
    expect(exportOrder("unit_id.asc")).toBe(
      "unit_id.asc,unit_type.asc,valid_from.asc,valid_to.asc"
    );
  });
});

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

describe("composeExportSelect", () => {
  it("prefixes external idents and suffixes stat definitions", () => {
    const select = composeExportSelect(baseData, "in.(establishment)");
    const columns = select.split(",");
    expect(columns[0]).toBe("org_no:external_idents->>org_no");
    expect(columns[1]).toBe("tax_ident:external_idents->>tax_ident");
    expect(columns.at(-2)).toBe("employees:stats_summary->employees->sum");
    expect(columns.at(-1)).toBe("turnover:stats_summary->turnover->sum");
  });

  it("omits unit_type when a single unit type is filtered", () => {
    const select = composeExportSelect(emptyBaseData, "in.(legal_unit)");
    expect(select.split(",")).not.toContain("unit_type");
  });

  it("includes unit_type when exporting mixed unit types", () => {
    const select = composeExportSelect(emptyBaseData, null);
    expect(select.split(",")).toContain("unit_type");
  });

  it("omits sector and legal form for establishments", () => {
    const select = composeExportSelect(emptyBaseData, "in.(establishment)");
    expect(select).not.toContain("sector_code");
    expect(select).not.toContain("legal_form_code");
  });

  it("includes sector and legal form for legal units", () => {
    const select = composeExportSelect(emptyBaseData, "in.(legal_unit)");
    expect(select).toContain("sector_code");
    expect(select).toContain("legal_form_code");
  });
});

describe("exportFieldNames", () => {
  it("extracts the output aliases in select order", () => {
    const fields = exportFieldNames(baseData, "in.(legal_unit)");
    expect(fields.slice(0, 4)).toEqual([
      "org_no",
      "tax_ident",
      "valid_from",
      "valid_to",
    ]);
    expect(fields).toContain("primary_activity_category_name");
    expect(fields).toContain("sector_code");
    expect(fields.slice(-2)).toEqual(["employees", "turnover"]);
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

describe("composeExportSearchParams", () => {
  it("keeps filters, replaces order/select, and strips pagination and format", () => {
    const input = new URLSearchParams({
      unit_type: "in.(establishment)",
      region: "in.(03)",
      order: "name.desc",
      limit: "10",
      offset: "20",
      select: "name",
      format: "csv",
    });
    const params = composeExportSearchParams(input, baseData);
    expect(params.get("unit_type")).toBe("in.(establishment)");
    expect(params.get("region")).toBe("in.(03)");
    expect(params.get("order")).toBe(
      "name.desc,unit_type.asc,unit_id.asc,valid_from.asc,valid_to.asc"
    );
    expect(params.get("select")).toBe(
      composeExportSelect(baseData, "in.(establishment)")
    );
    expect(params.get("limit")).toBeNull();
    expect(params.get("offset")).toBeNull();
    expect(params.get("format")).toBeNull();
  });

  it("does not mutate the input params", () => {
    const input = new URLSearchParams({ limit: "10" });
    composeExportSearchParams(input, baseData);
    expect(input.get("limit")).toBe("10");
    expect(input.get("select")).toBeNull();
  });

  it("preserves repeated filter params (multi-condition filters)", () => {
    const input = new URLSearchParams();
    input.append("physical_region_code", "in.(03)");
    input.append("physical_region_code", "is.null");
    const params = composeExportSearchParams(input, emptyBaseData);
    expect(params.getAll("physical_region_code")).toEqual([
      "in.(03)",
      "is.null",
    ]);
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
