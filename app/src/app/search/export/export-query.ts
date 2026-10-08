/**
 * Small shared pieces of the statistical-unit export (STATBUS-421).
 *
 * The export itself is ONE mechanism: the server route `/api/search/export`
 * streams `COPY (SELECT ...) TO STDOUT` as the user's own role; the SELECT,
 * its column order, filters and ORDER BY are composed in `export-sql.ts`.
 * The browser no longer composes a PostgREST select for exports (the
 * direct-REST path was retired in STATBUS-421 S5).
 */

// The xlsx row limits are defined once, in @/lib/excel-limits.
export { EXCEL_MAX_ROWS, EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";

/**
 * Above this many rows an .xlsx export requires explicit confirmation:
 * Excel itself struggles to open workbooks that large.
 */
export const EXCEL_CONFIRM_ROWS = 100_000;

export interface UnitTypeSelection {
  /** The raw unit_type filter value with the `in.(...)` wrapper removed. */
  unitType: string;
  /** True when the filter selects exactly one unit type. */
  hasSingleUnitType: boolean;
  isEstablishment: boolean;
}

export function parseUnitTypeFilter(
  unitTypeFilter: string | null
): UnitTypeSelection {
  const unitType = (unitTypeFilter ?? "").replace(/in\.\(|\)/g, "");
  const hasSingleUnitType = unitType !== "" && !unitType.includes(",");
  return {
    unitType,
    hasSingleUnitType,
    isEstablishment: unitType === "establishment",
  };
}

/** Download filename base, e.g. "establishments" or "statistical_units". */
export function exportBaseName(unitTypeFilter: string | null): string {
  const { unitType, hasSingleUnitType } = parseUnitTypeFilter(unitTypeFilter);
  return hasSingleUnitType ? `${unitType}s` : "statistical_units";
}
