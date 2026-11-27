import { qualitySearchResource } from "./quality-search";

// 05pe0x, owner decision 2026-11-26, h9mhxe: a quality search reads a check from its store first when
// the check lists fewer than QUALITY_FINDINGS_FIRST_BELOW units at the time frame
// (rpc/statistical_unit_quality), and walks statistical_unit in the page's order otherwise: a row
// check by its id in quality_check_ids, a relation check with its table as an inner embed. The other
// filters, order and paging are the same on every path.
const base = () =>
  new URLSearchParams(
    "unit_type=in.(legal_unit,establishment)&existence_from=lte.2026-11-24&existence_until=gt.2026-11-24&order=name.asc,unit_type.asc,unit_id.asc&limit=10&offset=0"
  );

describe("quality search resource", () => {
  it("reads a check of few units from its store, with the time frame as the function's instant", () => {
    const { path, params } = qualitySearchResource(
      base(),
      { id: 1, rule: "missing_region", kind: "row" },
      2
    );
    expect(path).toBe("rpc/statistical_unit_quality");
    expect(params.get("quality_check_id")).toBe("1");
    expect(params.get("valid_on")).toBe("2026-11-24");
    expect(params.has("existence_from")).toBe(false);
    expect(params.has("existence_until")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit,establishment)");
    expect(params.get("order")).toBe("name.asc,unit_type.asc,unit_id.asc");
    expect(params.get("limit")).toBe("10");
  });

  it("passes a per-variable check by its own id to the function", () => {
    const { path, params } = qualitySearchResource(
      base(),
      { id: 101, rule: "establishments_above_legal_unit", kind: "relation" },
      17
    );
    expect(path).toBe("rpc/statistical_unit_quality");
    expect(params.get("quality_check_id")).toBe("101");
  });

  it("walks statistical_unit by its quality_check_ids for a row check of many units", () => {
    const { path, params } = qualitySearchResource(
      base(),
      { id: 2, rule: "missing_activity_category", kind: "row" },
      161571
    );
    expect(path).toBe("statistical_unit");
    expect(params.get("quality_check_ids")).toBe("cs.{2}");
    expect(params.has("select")).toBe(false);
    expect(params.get("existence_from")).toBe("lte.2026-11-24");
    expect(params.get("existence_until")).toBe("gt.2026-11-24");
    expect(params.get("order")).toBe("name.asc,unit_type.asc,unit_id.asc");
  });

  it("embeds the check's table for a relation check of many units", () => {
    const differs = qualitySearchResource(
      base(),
      { id: 4, rule: "establishment_activity_differs", kind: "relation" },
      11008
    );
    expect(differs.path).toBe("statistical_unit");
    expect(differs.params.get("select")).toBe("*,quality_establishment_activity_differs!inner()");
    expect(differs.params.get("quality_establishment_activity_differs.check_id")).toBe("eq.4");

    const stat = qualitySearchResource(
      base(),
      { id: 103, rule: "legal_unit_above_establishments", kind: "relation" },
      5000
    );
    expect(stat.params.get("select")).toBe("*,quality_legal_unit_establishment_stat!inner()");
    expect(stat.params.get("quality_legal_unit_establishment_stat.check_id")).toBe("eq.103");
  });

  it("switches at the threshold: below it from the store, at it by walking the units", () => {
    const check = { id: 3, rule: "missing_physical_location" as const, kind: "row" as const };
    expect(qualitySearchResource(base(), check, 999).path).toBe("rpc/statistical_unit_quality");
    expect(qualitySearchResource(base(), check, 1000).path).toBe("statistical_unit");
  });
});
