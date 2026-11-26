import { qualitySearchResource } from "./quality-search";

// 05pe0x, owner decision 2026-11-26: a quality search reads a check from the findings first when the
// check lists fewer than QUALITY_FINDINGS_FIRST_BELOW units at the time frame
// (rpc/statistical_unit_quality), and walks statistical_unit in the page's order with the findings
// as an inner embed otherwise. The other filters, order and paging are the same on both.
const base = () =>
  new URLSearchParams(
    "unit_type=in.(legal_unit,establishment)&existence_from=lte.2026-11-24&existence_until=gt.2026-11-24&order=name.asc,unit_type.asc,unit_id.asc&limit=10&offset=0"
  );

describe("quality search resource", () => {
  it("reads a check of few units from the findings, with the time frame as the function's instant", () => {
    const { path, params } = qualitySearchResource(base(), { rule: "missing_region", statDefinitionId: null }, 2);
    expect(path).toBe("rpc/statistical_unit_quality");
    expect(params.get("quality_rule")).toBe("missing_region");
    expect(params.get("valid_on")).toBe("2026-11-24");
    expect(params.has("quality_stat_definition_id")).toBe(false);
    expect(params.has("existence_from")).toBe(false);
    expect(params.has("existence_until")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit,establishment)");
    expect(params.get("order")).toBe("name.asc,unit_type.asc,unit_id.asc");
    expect(params.get("limit")).toBe("10");
  });

  it("passes the variable of a per-variable check to the function", () => {
    const { path, params } = qualitySearchResource(
      base(),
      { rule: "establishments_above_legal_unit", statDefinitionId: 1 },
      17
    );
    expect(path).toBe("rpc/statistical_unit_quality");
    expect(params.get("quality_stat_definition_id")).toBe("1");
  });

  it("walks statistical_unit with the findings embedded for a check of many units", () => {
    const { path, params } = qualitySearchResource(
      base(),
      { rule: "missing_activity_category", statDefinitionId: null },
      161571
    );
    expect(path).toBe("statistical_unit");
    expect(params.get("select")).toBe("*,quality_finding!inner()");
    expect(params.get("quality_finding.rule")).toBe("eq.missing_activity_category");
    expect(params.get("quality_finding.stat_definition_id")).toBe("is.null");
    expect(params.get("existence_from")).toBe("lte.2026-11-24");
    expect(params.get("existence_until")).toBe("gt.2026-11-24");
    expect(params.get("order")).toBe("name.asc,unit_type.asc,unit_id.asc");
  });

  it("names the variable in the embed for a per-variable check of many units", () => {
    const { params } = qualitySearchResource(
      base(),
      { rule: "legal_unit_above_establishments", statDefinitionId: 2 },
      5000
    );
    expect(params.get("quality_finding.stat_definition_id")).toBe("eq.2");
  });

  it("switches at the threshold: below it from the findings, at it by walking the units", () => {
    const check = { rule: "missing_physical_location" as const, statDefinitionId: null };
    expect(qualitySearchResource(base(), check, 999).path).toBe("rpc/statistical_unit_quality");
    expect(qualitySearchResource(base(), check, 1000).path).toBe("statistical_unit");
  });
});
