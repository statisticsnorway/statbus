/**
 * Shared definition of the statistical-unit export query (STATBUS-421).
 *
 * The browser calls PostgREST (`/rest/statistical_unit`) directly with
 * `Accept: text/csv` — there is no `/api/search/export` proxy. This module is
 * the ONE place that composes the export `select` list and the export `order`;
 * both the search page export and the unit-history export build their request
 * through `composeExportSearchParams`.
 */

import type { Tables } from "@/lib/database.types";

/** The xlsx file format supports at most 1,048,576 rows; one is the header. */
export const EXCEL_MAX_ROWS = 1_048_576;
export const EXCEL_MAX_DATA_ROWS = EXCEL_MAX_ROWS - 1;

/**
 * Above this many rows an .xlsx export requires explicit confirmation:
 * Excel itself struggles to open workbooks that large.
 */
export const EXCEL_CONFIRM_ROWS = 100_000;

/** Base data needed to compose the export select list. */
export interface ExportBaseData {
  externalIdentTypes: ReadonlyArray<
    Pick<Tables<"external_ident_type_enabled">, "code">
  >;
  statDefinitions: ReadonlyArray<
    Pick<Tables<"stat_definition_enabled">, "code">
  >;
}

/**
 * A unit can have multiple temporal rows. Together these columns identify a
 * row of statistical_unit_def, even when names and dates are shared, so they
 * are appended as deterministic tiebreakers after the user's chosen order.
 */
export function exportOrder(order: string | null): string {
  const columns = (order || "name.asc").split(",").map((part) => part.trim());
  for (const key of ["unit_type", "unit_id", "valid_from", "valid_to"]) {
    if (!columns.some((column) => column.split(".")[0] === key)) {
      columns.push(`${key}.asc`);
    }
  }
  return columns.join(",");
}

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

/**
 * The export column list: external idents first, then the shared columns,
 * then statistical variables — matching the historical export layout.
 */
export function composeExportSelect(
  baseData: ExportBaseData,
  unitTypeFilter: string | null
): string {
  const { hasSingleUnitType, isEstablishment } =
    parseUnitTypeFilter(unitTypeFilter);

  const externalIdentColumns = baseData.externalIdentTypes.map(
    ({ code }) => `${code}:external_idents->>${code}`
  );
  const statDefinitionColumns = baseData.statDefinitions.map(
    ({ code }) => `${code}:stats_summary->${code}->sum`
  );

  return [
    externalIdentColumns,
    [
      "valid_from",
      "valid_to",
      "name",
      ...(hasSingleUnitType ? [] : ["unit_type"]),
      "birth_date",
      "death_date",
      "primary_activity_category_code",
      "primary_activity_category_name:primary_activity_category->>name",
      "secondary_activity_category_code",
      "secondary_activity_category_name:secondary_activity_category->>name",
      ...(isEstablishment ? [] : ["sector_code", "legal_form_code"]),
      "physical_address_part1",
      "physical_address_part2",
      "physical_address_part3",
      "physical_postcode",
      "physical_postplace",
      "physical_region_code",
      "physical_region_name:physical_region->>name",
      "physical_country_iso_2",
      // Coordinates are numeric(?,6)/numeric(?,1): PostgREST's CSV preserves
      // the scale (63.000000) where JSON gave the shortest form (63). The
      // float8 cast (shortest round-trip text) keeps the CSV identical to
      // the historical export.
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
    ],
    statDefinitionColumns,
  ]
    .flat()
    .join(",");
}

/** The field names (aliases) the composed select produces, in order. */
export function exportFieldNames(
  baseData: ExportBaseData,
  unitTypeFilter: string | null
): string[] {
  return composeExportSelect(baseData, unitTypeFilter)
    .split(",")
    .map((part) => part.split(":")[0].trim())
    .filter(Boolean);
}

/** Download filename base, e.g. "establishments" or "statistical_units". */
export function exportBaseName(unitTypeFilter: string | null): string {
  const { unitType, hasSingleUnitType } = parseUnitTypeFilter(unitTypeFilter);
  return hasSingleUnitType ? `${unitType}s` : "statistical_units";
}

/**
 * Compose the PostgREST query for a full export from the search page's
 * filter params: same filters and order (plus export tiebreakers), the
 * composed export select, and no limit/offset — the export streams the
 * entire matching set in one request.
 */
export function composeExportSearchParams(
  searchParams: URLSearchParams,
  baseData: ExportBaseData
): URLSearchParams {
  const params = new URLSearchParams(searchParams);
  // The export never pages: strip pagination, any pre-set select, and the
  // format hint (format chooses the Accept header, not a query param).
  params.delete("limit");
  params.delete("offset");
  params.delete("select");
  params.delete("format");
  params.set("order", exportOrder(params.get("order")));
  params.set("select", composeExportSelect(baseData, params.get("unit_type")));
  return params;
}
