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

  // STATBUS-421: the arrow form (`alias:rel->>name`) on a SETOF computed
  // relationship drops the row when every such call returns an empty set.
  it("projects relationship names with the spread syntax, never the arrow form", () => {
    const columns = composeExportSelect(emptyBaseData, null).split(",");
    expect(columns).toEqual(
      expect.arrayContaining([
        "...primary_activity_category(primary_activity_category_name:name)",
        "...secondary_activity_category(secondary_activity_category_name:name)",
        "...physical_region(physical_region_name:name)",
      ])
    );
    expect(columns.filter((column) => column.includes("->>name"))).toEqual([]);
  });

  it("keeps the full column list and order for a mixed export", () => {
    expect(composeExportSelect(baseData, "in.(legal_unit,establishment)")).toBe(
      [
        "org_no:external_idents->>org_no",
        "tax_ident:external_idents->>tax_ident",
        "valid_from",
        "valid_to",
        "name",
        "unit_type",
        "birth_date",
        "death_date",
        "primary_activity_category_code",
        "...primary_activity_category(primary_activity_category_name:name)",
        "secondary_activity_category_code",
        "...secondary_activity_category(secondary_activity_category_name:name)",
        "sector_code",
        "legal_form_code",
        "physical_address_part1",
        "physical_address_part2",
        "physical_address_part3",
        "physical_postcode",
        "physical_postplace",
        "physical_region_code",
        "...physical_region(physical_region_name:name)",
        "physical_country_iso_2",
        "physical_latitude:physical_latitude::float8",
        "physical_longitude:physical_longitude::float8",
        "physical_altitude:physical_altitude::float8",
        "postal_address_part1",
        "postal_address_part2",
        "postal_address_part3",
        "postal_postcode",
        "postal_postplace",
        "postal_country_iso_2",
        "web_address",
        "email_address",
        "phone_number",
        "landline",
        "mobile_number",
        "fax_number",
        "status_code",
        "unit_size_code",
        "employees:stats_summary->employees->sum",
        "turnover:stats_summary->turnover->sum",
      ].join(",")
    );
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

  it("names spread columns by their inner alias, keeping the historical order", () => {
    const fields = exportFieldNames(emptyBaseData, "in.(establishment)");
    const primary = fields.indexOf("primary_activity_category_code");
    expect(fields.slice(primary, primary + 4)).toEqual([
      "primary_activity_category_code",
      "primary_activity_category_name",
      "secondary_activity_category_code",
      "secondary_activity_category_name",
    ]);
    const region = fields.indexOf("physical_region_name");
    expect(fields[region - 1]).toBe("physical_region_code");
    expect(fields[region + 1]).toBe("physical_country_iso_2");
    expect(fields.filter((field) => /[.(]/.test(field))).toEqual([]);
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
  it.each([
    null,
    "in.(legal_unit)",
    "in.(establishment)",
    "in.(enterprise)",
    "in.(legal_unit,establishment)",
  ])("only applies arrow projections to stored JSON for %s", (unitType) => {
    // Check the select actually sent, not source text or a particular field
    // token. SETOF relationship arrows can change the number of export rows
    // even when projecting a field other than name (STATBUS-462).
    const input = new URLSearchParams({
      select: "old_alias:physical_region->>name",
      limit: "10",
      offset: "20",
    });
    if (unitType) input.set("unit_type", unitType);

    for (const definitions of [emptyBaseData, baseData]) {
      const params = composeExportSearchParams(input, definitions);
      const select = params.get("select")!;
      const arrowRoots = Array.from(
        select.matchAll(/(?:^|,)\s*(?:[^:(),]+:)?([a-z_][a-z_0-9]*)\s*->/g),
        (match) => match[1]
      );
      // These are jsonb columns, not functions returning SETOF. Checking
      // every root also rejects arrows on any other computed relationship.
      expect(arrowRoots).toEqual(
        definitions === emptyBaseData
          ? []
          : [
              "external_idents",
              "external_idents",
              "stats_summary",
              "stats_summary",
            ]
      );
      expect(select.split(",")).toEqual(
        expect.arrayContaining([
          "...primary_activity_category(primary_activity_category_name:name)",
          "...secondary_activity_category(secondary_activity_category_name:name)",
          "...physical_region(physical_region_name:name)",
        ])
      );
    }
  });

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
