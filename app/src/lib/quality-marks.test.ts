import {
  qualityMarkKey,
  qualityMarkPlace,
  qualityMarksByPlace,
  unitQualityFindings,
  type ShownQualityCheck,
} from "./quality-marks";

// b6f1pw: a unit's pages mark the field a quality check points at, for the checks the reports show.
const SHOWN: ShownQualityCheck[] = [
  { id: 1, rule: "missing_region", stat_definition_id: null },
  { id: 2, rule: "missing_activity_category", stat_definition_id: null },
  { id: 4, rule: "establishment_activity_differs", stat_definition_id: null },
  { id: 7, rule: "secondary_activity_equals_primary", stat_definition_id: null },
  { id: 101, rule: "establishments_above_legal_unit", stat_definition_id: 1 },
];
const STAT_NAMES = new Map([[1, "Employees"]]);

describe("unit quality findings", () => {
  it("keeps the listed checks the reports show, with the variable's name", () => {
    expect(unitQualityFindings([7, 101], SHOWN, STAT_NAMES)).toEqual([
      { checkId: 7, rule: "secondary_activity_equals_primary", statDefinitionId: null, statName: null },
      { checkId: 101, rule: "establishments_above_legal_unit", statDefinitionId: 1, statName: "Employees" },
    ]);
  });

  it("marks nothing for a listed check that is switched off or not in use", () => {
    expect(unitQualityFindings([3, 103], SHOWN, STAT_NAMES)).toEqual([]);
  });
});

describe("quality mark place", () => {
  it("points the secondary activity check at the secondary activity field", () => {
    const [finding] = unitQualityFindings([7], SHOWN, STAT_NAMES);
    expect(qualityMarkKey(qualityMarkPlace(finding))).toBe("secondary_activity");
  });

  it("points a per-variable check at its variable's field", () => {
    const [finding] = unitQualityFindings([101], SHOWN, STAT_NAMES);
    expect(qualityMarkKey(qualityMarkPlace(finding))).toBe("stat:1");
  });

  it("groups the activity checks on the primary activity field", () => {
    const byPlace = qualityMarksByPlace(unitQualityFindings([2, 4, 1], SHOWN, STAT_NAMES));
    expect(byPlace.get("primary_activity")?.map((f) => f.rule)).toEqual([
      "missing_activity_category",
      "establishment_activity_differs",
    ]);
    expect(byPlace.get("physical_location")?.map((f) => f.rule)).toEqual(["missing_region"]);
  });
});
