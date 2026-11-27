import type { QualityRule } from "@/lib/quality-checks";

/**
 * The place on a unit's pages that a quality check points at (b6f1pw): the field or group someone
 * opens to correct what the check lists.
 *  - physical_location: General info, the Physical Location group (its region and country).
 *  - primary_activity / secondary_activity: Classifications, the activity category fields.
 *  - stat: Statistical variables, the field of the check's variable.
 */
export type QualityMarkPlace =
  | { readonly field: "physical_location" }
  | { readonly field: "primary_activity" }
  | { readonly field: "secondary_activity" }
  | { readonly field: "stat"; readonly statDefinitionId: number };

/**
 * The field each rule points at. Keyed by the database enum, so a rule added to public.quality_rule
 * fails the type check until it names its field. A per-variable rule points at its variable.
 */
const RULE_FIELD: Record<QualityRule, QualityMarkPlace["field"]> = {
  missing_region: "physical_location",
  missing_physical_location: "physical_location",
  missing_activity_category: "primary_activity",
  establishment_activity_differs: "primary_activity",
  secondary_activity_equals_primary: "secondary_activity",
  establishments_above_legal_unit: "stat",
  legal_unit_above_establishments: "stat",
};

/** A check this unit fails at the instant shown: its rule, and its variable for a per-variable rule. */
export interface UnitQualityFinding {
  readonly checkId: number;
  readonly rule: QualityRule;
  readonly statDefinitionId: number | null;
  readonly statName: string | null;
}

/** The key of a place, so a page looks its marks up by field. */
export function qualityMarkKey(place: QualityMarkPlace): string {
  return place.field === "stat" ? `stat:${place.statDefinitionId}` : place.field;
}

export function qualityMarkPlace(finding: UnitQualityFinding): QualityMarkPlace {
  const field = RULE_FIELD[finding.rule];
  if (field !== "stat") return { field };
  if (finding.statDefinitionId === null) {
    throw new Error(`The per-variable check ${finding.rule} (${finding.checkId}) names no variable`);
  }
  return { field, statDefinitionId: finding.statDefinitionId };
}

/** The findings of a unit grouped by the place they mark, keyed by qualityMarkKey. */
export function qualityMarksByPlace(
  findings: readonly UnitQualityFinding[]
): ReadonlyMap<string, readonly UnitQualityFinding[]> {
  const byPlace = new Map<string, UnitQualityFinding[]>();
  for (const finding of findings) {
    const key = qualityMarkKey(qualityMarkPlace(finding));
    byPlace.set(key, [...(byPlace.get(key) ?? []), finding]);
  }
  return byPlace;
}

/** A check of public.quality_check that is switched on and in use, as the unit pages read it. */
export interface ShownQualityCheck {
  readonly id: number;
  readonly rule: QualityRule;
  readonly stat_definition_id: number | null;
}

/**
 * A unit's findings from the ids it is listed under (its statistical_unit row's quality_check_ids
 * and its rows in the relation tables), kept to the checks the reports show: switched on and in
 * use. An id outside that set is a check the dashboard does not show either, so it marks nothing.
 */
export function unitQualityFindings(
  listedCheckIds: readonly number[],
  shownChecks: readonly ShownQualityCheck[],
  statNameById: ReadonlyMap<number, string>
): UnitQualityFinding[] {
  const listed = new Set(listedCheckIds);
  return shownChecks
    .filter((check) => listed.has(check.id))
    .map((check) => ({
      checkId: check.id,
      rule: check.rule,
      statDefinitionId: check.stat_definition_id,
      statName:
        check.stat_definition_id === null ? null : statNameById.get(check.stat_definition_id) ?? null,
    }));
}
