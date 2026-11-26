import {
  QUALITY_RULE_UNIT_TYPES,
  QUALITY_RULE_WORDING,
  parseQualityCheckParam,
  qualityCheckHref,
  qualityCheckName,
  qualityCheckParam,
  type QualityRule,
} from "./quality-checks";
import { Constants } from "./database.types";

// 05pe0x: a data-quality check is a rule of public.quality_rule and, for a per-variable rule, the
// variable. Its name, ⓘ text and search link are made here from the rule and the variable's
// stat_definition name and code.
const RULES = Constants.public.Enums.quality_rule as readonly QualityRule[];

describe("quality check wording", () => {
  it("has a name and an explanation for every rule of the database enum", () => {
    expect(Object.keys(QUALITY_RULE_WORDING).sort()).toEqual([...RULES].sort());
    for (const rule of RULES) {
      expect(qualityCheckName(rule, "Employees")).not.toEqual("");
      expect(QUALITY_RULE_WORDING[rule].explanation("Employees")).not.toEqual("");
    }
  });

  it("names a per-variable check after its variable", () => {
    expect(qualityCheckName("establishments_above_legal_unit", "Employees")).toBe(
      "Employees: establishments add up to more than the legal unit"
    );
    expect(qualityCheckName("legal_unit_above_establishments", "Turnover")).toBe(
      "Turnover: legal unit has more than its establishments, all of which have numbers"
    );
  });
});

describe("quality check search link", () => {
  it("writes the rule, and the variable code for a per-variable rule", () => {
    expect(qualityCheckParam("missing_region", null)).toBe("missing_region");
    expect(qualityCheckParam("establishments_above_legal_unit", "employees")).toBe(
      "establishments_above_legal_unit:employees"
    );
  });

  it("reads back what it writes, and nothing else", () => {
    expect(parseQualityCheckParam("missing_region")).toEqual({ rule: "missing_region", statCode: null });
    expect(parseQualityCheckParam("legal_unit_above_establishments:turnover")).toEqual({
      rule: "legal_unit_above_establishments",
      statCode: "turnover",
    });
    expect(parseQualityCheckParam("unknown_rule")).toBeNull();
    expect(parseQualityCheckParam("missing_region:a:b")).toBeNull();
    expect(parseQualityCheckParam(null)).toBeNull();
  });

  it("opens the unit types the check lists", () => {
    expect(qualityCheckHref("missing_physical_location", null)).toBe(
      "/search?unit_type=legal_unit,establishment&quality=missing_physical_location"
    );
    expect(qualityCheckHref("establishments_above_legal_unit", "employees")).toBe(
      "/search?unit_type=legal_unit&quality=establishments_above_legal_unit:employees"
    );
    expect(Object.keys(QUALITY_RULE_UNIT_TYPES).sort()).toEqual([...RULES].sort());
  });
});
