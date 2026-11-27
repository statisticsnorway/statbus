import { fetchWithAuthRefresh } from "@/context/RestClientStore";

/**
 * A variable's total over the units of a region, as statistical_unit_facet's stats_summary
 * holds it (jsonb_stats int_agg/float_agg): `sum` is the total, `count` how many units carry
 * a value, so sum / count is their mean.
 */
export interface VariableTotal {
  sum: number;
  count: number;
}

/** One region's measures for one unit type at one date. */
export interface RegionMeasures {
  path: string;
  units: number;
  totals: Record<string, VariableTotal>;
}

/**
 * Two ways to read the measures, compared on the page until the owner picks one (ppvxg2,
 * tmp/ppvxg2-proto.md): B sums statistical_unit_facet with PostgREST aggregates and rolls the
 * leaf paths up in the browser; C′ calls a function that returns one row per child region with
 * its merged stats_summary.
 */
export type ReadStrategy = "B" | "Cp";

export interface Read {
  rows: RegionMeasures[];
  ms: number;
  bytes: number;
  url: string;
}

async function getJson(url: string) {
  const started = performance.now();
  const response = await fetchWithAuthRefresh(url, { headers: { Accept: "application/json" } });
  const text = await response.text();
  const ms = Math.round(performance.now() - started);
  if (!response.ok) throw new Error(`${response.status} ${text.slice(0, 300)}`);
  return { json: JSON.parse(text) as unknown, ms, bytes: text.length };
}

type FacetRow = Record<string, number | string | null>;

/**
 * Facet rows summed per leaf region path, rolled up to the children of `at` (B). A row on `at`
 * itself (a unit placed on the selection, not on one of its children) keeps the path `at`.
 */
export function rollUp(rows: FacetRow[], at: string, codes: readonly string[]): RegionMeasures[] {
  const depth = at ? at.split(".").length + 1 : 1;
  const byChild = new Map<string, RegionMeasures>();
  for (const row of rows) {
    const path = row.physical_region_path;
    if (typeof path !== "string") continue;
    if (at && path !== at && !path.startsWith(`${at}.`)) continue;
    const child = path.split(".").slice(0, depth).join(".");
    const entry = byChild.get(child) ?? { path: child, units: 0, totals: {} };
    entry.units += Number(row.units ?? 0);
    for (const code of codes) {
      const total = entry.totals[code] ?? { sum: 0, count: 0 };
      total.sum += Number(row[`s_${code}`] ?? 0);
      total.count += Number(row[`n_${code}`] ?? 0);
      entry.totals[code] = total;
    }
    byChild.set(child, entry);
  }
  return [...byChild.values()];
}

export async function readMeasures(
  strategy: ReadStrategy,
  unitType: UnitType,
  at: string,
  validOn: string,
  codes: readonly string[]
): Promise<Read> {
  if (strategy === "B") {
    const sums = codes
      .map(
        (c) =>
          `,s_${c}:stats_summary->${c}->sum::numeric.sum(),n_${c}:stats_summary->${c}->count::numeric.sum()`
      )
      .join("");
    const url =
      `/rest/statistical_unit_facet?select=physical_region_path,units:count.sum()${sums}` +
      `&valid_from=lte.${validOn}&valid_until=gt.${validOn}&unit_type=eq.${unitType}` +
      (at ? `&physical_region_path=cd.${at}` : "");
    const { json, ms, bytes } = await getJson(url);
    return { rows: rollUp(json as FacetRow[], at, codes), ms, bytes, url };
  }
  const picks = codes
    .map((c) => `,s_${c}:stats_summary->${c}->sum,n_${c}:stats_summary->${c}->count`)
    .join("");
  const url =
    `/rest/rpc/ppvxg2_proto_region_stats?unit_type=${unitType}&valid_on=${validOn}` +
    (at ? `&parent_path=${at}` : "") +
    `&select=path,count${picks}`;
  const { json, ms, bytes } = await getJson(url);
  const rows = (json as FacetRow[])
    .filter((r) => Number(r.count ?? 0) > 0)
    .map((r) => ({
      path: String(r.path),
      units: Number(r.count),
      totals: Object.fromEntries(
        codes.map((c) => [c, { sum: Number(r[`s_${c}`] ?? 0), count: Number(r[`n_${c}`] ?? 0) }])
      ),
    }));
  return { rows, ms, bytes, url };
}

/** The units of one region, largest first by the variable that sizes the map, or by name. */
export interface RegionUnit {
  unit_type: UnitType;
  unit_id: number;
  name: string;
  primary_activity_category_code: string | null;
  physical_region_code: string | null;
  physical_postplace: string | null;
  stats_summary: Record<string, { sum?: number; count?: number } | string> | null;
}

export async function readRegionUnits(
  unitType: UnitType,
  path: string,
  validOn: string,
  sizeBy: string
): Promise<RegionUnit[]> {
  const order = sizeBy === "units" ? "name.asc" : `stats_summary->${sizeBy}->sum.desc.nullslast,name.asc`;
  const url =
    `/rest/statistical_unit?select=unit_type,unit_id,name,primary_activity_category_code,physical_region_code,physical_postplace,stats_summary` +
    `&unit_type=eq.${unitType}&physical_region_path=cd.${path}` +
    `&existence_from=lte.${validOn}&existence_until=gt.${validOn}&order=${order}&limit=25`;
  const { json } = await getJson(url);
  return json as RegionUnit[];
}

/**
 * The selection's totals for every unit type side by side (as Erik's legend in PR #325 gave them),
 * one facet read grouped by unit type. Each type's total is its own: they are not added across
 * types, since establishments are parts of legal units and legal units of enterprises.
 */
export async function readTypeTotals(
  at: string,
  validOn: string,
  codes: readonly string[]
): Promise<(RegionMeasures & { unit_type: UnitType })[]> {
  const sums = codes
    .map(
      (c) =>
        `,s_${c}:stats_summary->${c}->sum::numeric.sum(),n_${c}:stats_summary->${c}->count::numeric.sum()`
    )
    .join("");
  const url =
    `/rest/statistical_unit_facet?select=unit_type,units:count.sum()${sums}` +
    `&valid_from=lte.${validOn}&valid_until=gt.${validOn}` +
    `&unit_type=in.(enterprise,legal_unit,establishment)` +
    (at ? `&physical_region_path=cd.${at}` : "");
  const { json } = await getJson(url);
  return (json as FacetRow[]).map((r) => ({
    unit_type: r.unit_type as UnitType,
    path: at,
    units: Number(r.units ?? 0),
    totals: Object.fromEntries(
      codes.map((c) => [c, { sum: Number(r[`s_${c}`] ?? 0), count: Number(r[`n_${c}`] ?? 0) }])
    ),
  }));
}
