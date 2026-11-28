import { fetchWithAuthRefresh } from "@/context/RestClientStore";

/** One unit of a region, as the Drilldown's map lists it at the lowest level. */
export interface RegionUnit {
  unit_type: UnitType;
  unit_id: number;
  name: string;
  stats_summary: Record<string, { sum?: number; count?: number } | string> | null;
}

/**
 * The first units of a region at a date, within the Drilldown's activity when one is chosen:
 * largest first by the primary variable, or by name when the primary is the number of units.
 */
export async function readRegionUnits(
  unitType: UnitType,
  regionPath: string,
  activityPath: string | null,
  validOn: string,
  primary: string
): Promise<RegionUnit[]> {
  const order = primary === "count" ? "name.asc" : `stats_summary->${primary}->sum.desc.nullslast,name.asc`;
  const url =
    `/rest/statistical_unit?select=unit_type,unit_id,name,stats_summary` +
    `&unit_type=eq.${unitType}&physical_region_path=cd.${regionPath}` +
    (activityPath ? `&primary_activity_category_path=cd.${activityPath}` : "") +
    `&existence_from=lte.${validOn}&existence_until=gt.${validOn}&order=${order}&limit=25`;
  const response = await fetchWithAuthRefresh(url, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`${response.status} ${(await response.text()).slice(0, 300)}`);
  return (await response.json()) as RegionUnit[];
}
