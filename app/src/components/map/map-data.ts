/**
 * What the maps draw, as plain data: no MapLibre here, so it is tested in jest's node
 * environment and the map components only hand these results to MapLibre.
 */
import type { Enums } from "@/lib/database.types";

export type UnitType = Enums<"statistical_unit_type">;

/** The unit types a map legend lets you pick, in the app's order (enterprise above its units). */
export const MAP_UNIT_TYPES = ["enterprise", "legal_unit", "establishment"] as const satisfies readonly UnitType[];
export type MapUnitType = (typeof MAP_UNIT_TYPES)[number];

export const UNIT_TYPE_LABEL: Record<MapUnitType, string> = {
  enterprise: "Enterprise",
  legal_unit: "Legal unit",
  establishment: "Establishment",
};

/**
 * Tailwind classes for each unit type's colour. Tailwind writes a theme colour's CSS variable
 * to the page only when a class uses it, so naming these classes here is also what puts
 * `--color-<type>-500` (and the grey `--color-informal-500` for mixed types) on the page for
 * the map's `cssColour` to read.
 */
export const UNIT_TYPE_SWATCH: Record<MapUnitType | "mixed", string> = {
  enterprise: "bg-enterprise-500",
  legal_unit: "bg-legal_unit-500",
  establishment: "bg-establishment-500",
  mixed: "bg-informal-500",
};

/**
 * The CSS variable that holds a unit type's colour, the same one the unit pages' headers and
 * icons use (app/src/app/globals.css), so the map shows enterprises, legal units and
 * establishments in the app's colours (owner 2026-11-22, z2qt08). MapLibre paints with
 * resolved colour strings, so the map reads the variable's value at run time.
 */
export function unitTypeColourVariable(unitType: MapUnitType, shade: 300 | 500 | 700 = 500): string {
  return `--color-${unitType}-${shade}`;
}

/** One facet row as read from statistical_unit_facet: a count of units of a type at a region path. */
export interface RegionCountRow {
  unit_type: UnitType | null;
  physical_region_path: string | null;
  /** The country of the unit's physical location; null when it has no physical location. */
  physical_country_id?: number | null;
  count: number | null;
}

/** A region of the region table, with its centre if it has one. */
export interface MapRegion {
  path: string;
  name: string;
  center_latitude: number | null;
  center_longitude: number | null;
}

/** Units per region path at one depth, split by unit type. */
export interface RegionCount {
  path: string;
  counts: Record<MapUnitType, number>;
}

/**
 * The first `depth` labels of an ltree path ("46.4601", depth 1 -> "46"). A path shorter than
 * the depth stays as it is: a unit placed on a county is counted at the county when the map
 * shows municipalities.
 */
export function pathPrefix(path: string, depth: number): string {
  return path.split(".").slice(0, depth).join(".");
}

/**
 * The region depth a map shows at a zoom: counties at country zoom, then one level deeper per
 * zoom band, down to the deepest level the region tree has (Norway 2, Morocco 5; z2qt08).
 */
export function depthForZoom(zoom: number, maxDepth: number, firstZoom = 6, zoomPerLevel = 1.5): number {
  if (maxDepth < 1) return 1;
  const depth = zoom < firstZoom ? 1 : 2 + Math.floor((zoom - firstZoom) / zoomPerLevel);
  return Math.min(Math.max(depth, 1), maxDepth);
}

/** The depth of the deepest region path. */
export function maxRegionDepth(regions: { path: string }[]): number {
  return regions.reduce((max, r) => Math.max(max, r.path.split(".").length), 0);
}

/**
 * Sums facet rows to one count per region path prefix at `depth`, per unit type. Rows without
 * a region, and unit types the map does not draw (power groups), are left out; the map lists
 * units without a region separately (`unplacedCount`).
 */
export function countsByRegion(rows: RegionCountRow[], depth: number): RegionCount[] {
  const byPath = new Map<string, RegionCount>();
  for (const row of rows) {
    if (!row.physical_region_path || !isMapUnitType(row.unit_type)) continue;
    const path = pathPrefix(row.physical_region_path, depth);
    let entry = byPath.get(path);
    if (!entry) {
      entry = { path, counts: { enterprise: 0, legal_unit: 0, establishment: 0 } };
      byPath.set(path, entry);
    }
    entry.counts[row.unit_type] += row.count ?? 0;
  }
  return [...byPath.values()].sort((a, b) => a.path.localeCompare(b.path));
}

/** Units of the drawn types that have no region, so no place on a regions map. */
export function unplacedCount(rows: RegionCountRow[], unitTypes: readonly MapUnitType[]): number {
  return rows
    .filter((r) => !r.physical_region_path && isMapUnitType(r.unit_type) && unitTypes.includes(r.unit_type))
    .reduce((sum, r) => sum + (r.count ?? 0), 0);
}

export function isMapUnitType(unitType: UnitType | null): unitType is MapUnitType {
  return unitType !== null && (MAP_UNIT_TYPES as readonly UnitType[]).includes(unitType);
}

/**
 * Where the Regions map stands (owner 2026-11-23, z2qt08): the world (null), the installation's
 * own country (""), a foreign country ("country:SE", by its ISO 3166 alpha-2 code), or a region
 * by its path ("50", "50.5001"). The selection alone decides what the map shows, its children,
 * and what the breadcrumb, the panel and the fit button refer to.
 */
export type MapSelection = string | null;

/** The ISO 3166 alpha-2 code of a selected foreign country, or null for any other selection. */
export function selectedCountryCode(selection: MapSelection): string | null {
  return selection?.startsWith("country:") ? selection.slice("country:".length) : null;
}

/** The selection's region path depth: the world -1, a country 0, a county 1, and so on. */
export function selectionDepth(selection: MapSelection): number {
  if (selection === null) return -1;
  return selection === "" || selectedCountryCode(selection) ? 0 : selection.split(".").length;
}

/** The selections from the world down to `selection`, for the breadcrumb: null, "", "50", "50.5001". */
export function selectionTrail(selection: MapSelection): MapSelection[] {
  if (selection === null) return [null];
  if (selectedCountryCode(selection)) return [null, selection];
  const labels = selection === "" ? [] : selection.split(".");
  return [null, "", ...labels.map((_, i) => labels.slice(0, i + 1).join("."))];
}

/** One step up: a region to its parent region or the country, a country to the world. */
export function selectionParent(selection: MapSelection): MapSelection {
  if (selection === null || selection === "" || selectedCountryCode(selection)) return null;
  return selection.split(".").slice(0, -1).join(".");
}

/** Units per type in each country, by country id; units without a physical location are left out. */
export function countryCounts(rows: RegionCountRow[]): Map<number, Record<MapUnitType, number>> {
  const byCountry = new Map<number, Record<MapUnitType, number>>();
  for (const r of rows) {
    if (r.physical_country_id == null || !isMapUnitType(r.unit_type)) continue;
    let c = byCountry.get(r.physical_country_id);
    if (!c) {
      c = { enterprise: 0, legal_unit: 0, establishment: 0 };
      byCountry.set(r.physical_country_id, c);
    }
    c[r.unit_type] += r.count ?? 0;
  }
  return byCountry;
}

/** A facet row of the installation's own country that lies in `selection` ("" is the whole country). */
function isUnder(row: RegionCountRow, selection: string, homeCountryId: number | null): boolean {
  if (row.physical_country_id != null && homeCountryId != null && row.physical_country_id !== homeCountryId) return false;
  if (selection === "") return row.physical_country_id != null && row.physical_country_id === homeCountryId;
  const path = row.physical_region_path;
  return path === selection || (path?.startsWith(`${selection}.`) ?? false);
}

/**
 * The regions one level below a domestic selection, with their units: the counties of the
 * country, the municipalities of a county. Units placed on the selected region itself, not on
 * one of its children, are counted at the region's own path, so a leaf region shows itself.
 */
export function childCounts(rows: RegionCountRow[], selection: string, homeCountryId: number | null): RegionCount[] {
  return countsByRegion(
    rows.filter((r) => isUnder(r, selection, homeCountryId)),
    selectionDepth(selection) + 1
  );
}

/** Units per type in a domestic selection, the region and everything below it. */
export function countsUnder(rows: RegionCountRow[], selection: string, homeCountryId: number | null): Record<MapUnitType, number> {
  const counts: Record<MapUnitType, number> = { enterprise: 0, legal_unit: 0, establishment: 0 };
  for (const r of rows) {
    if (isMapUnitType(r.unit_type) && isUnder(r, selection, homeCountryId)) counts[r.unit_type] += r.count ?? 0;
  }
  return counts;
}

/**
 * The world split of the picked unit types: units in the installation's own country, those of
 * them without a region, units abroad by country (largest first), and units with no physical
 * location, which have no country (owner 2026-11-23: domestic and abroad both at the top).
 */
export function worldCounts(
  rows: RegionCountRow[],
  homeCountryId: number | null,
  unitTypes: readonly MapUnitType[]
): { domestic: number; domesticWithoutRegion: number; abroad: { countryId: number; count: number }[]; noLocation: number } {
  let domestic = 0;
  let domesticWithoutRegion = 0;
  let noLocation = 0;
  const abroad = new Map<number, number>();
  for (const r of rows) {
    if (!isMapUnitType(r.unit_type) || !unitTypes.includes(r.unit_type)) continue;
    const n = r.count ?? 0;
    if (r.physical_country_id == null) noLocation += n;
    else if (r.physical_country_id === homeCountryId) {
      domestic += n;
      if (!r.physical_region_path) domesticWithoutRegion += n;
    } else abroad.set(r.physical_country_id, (abroad.get(r.physical_country_id) ?? 0) + n);
  }
  return {
    domestic,
    domesticWithoutRegion,
    abroad: [...abroad].map(([countryId, count]) => ({ countryId, count })).sort((a, b) => b.count - a.count),
    noLocation,
  };
}

/** A region's units of the picked types. */
export function selectedTotal(counts: Record<MapUnitType, number>, unitTypes: readonly MapUnitType[]): number {
  return unitTypes.reduce((sum, t) => sum + counts[t], 0);
}

export interface RegionFeatureProperties {
  path: string;
  name: string;
  total: number;
  enterprise: number;
  legal_unit: number;
  establishment: number;
}

/**
 * The regions with a centre and at least one unit of the picked types, as GeoJSON points, and
 * the regions the map cannot place because they have no centre (listed beside the map).
 */
export function regionFeatures(
  regions: MapRegion[],
  counts: RegionCount[],
  unitTypes: readonly MapUnitType[]
): {
  features: GeoJSON.FeatureCollection<GeoJSON.Point, RegionFeatureProperties>;
  withoutCentre: { path: string; name: string; total: number }[];
} {
  const regionByPath = new Map(regions.map((r) => [r.path, r]));
  const features: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>[] = [];
  const withoutCentre: { path: string; name: string; total: number }[] = [];
  for (const { path, counts: c } of counts) {
    const total = selectedTotal(c, unitTypes);
    if (total === 0) continue;
    const region = regionByPath.get(path);
    const name = region?.name ?? path;
    if (region?.center_latitude == null || region.center_longitude == null) {
      withoutCentre.push({ path, name, total });
      continue;
    }
    features.push({
      type: "Feature",
      geometry: { type: "Point", coordinates: [Number(region.center_longitude), Number(region.center_latitude)] },
      properties: { path, name, total, enterprise: c.enterprise, legal_unit: c.legal_unit, establishment: c.establishment },
    });
  }
  return { features: { type: "FeatureCollection", features }, withoutCentre };
}

/** The bounds [west, south, east, north] that hold every feature, or null for none. */
export function featureBounds(features: GeoJSON.Feature<GeoJSON.Point>[]): [number, number, number, number] | null {
  if (features.length === 0) return null;
  let [west, south, east, north] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const f of features) {
    const [lon, lat] = f.geometry.coordinates;
    west = Math.min(west, lon);
    east = Math.max(east, lon);
    south = Math.min(south, lat);
    north = Math.max(north, lat);
  }
  return [west, south, east, north];
}

/**
 * The regions a map first frames: those with at least `share` of the largest region's units.
 * A far-off region with few units (Svalbard's 643 legal units against Oslo's 188,463) stays on
 * the map but does not shrink the country to fit it.
 */
export function framingFeatures<P extends { total: number }>(
  features: GeoJSON.Feature<GeoJSON.Point, P>[],
  share = 0.01
): GeoJSON.Feature<GeoJSON.Point, P>[] {
  const max = maxTotal(features);
  return features.filter((f) => f.properties.total >= max * share);
}

/** The largest region total, the top of the circle-size scale. */
export function maxTotal(features: GeoJSON.Feature<GeoJSON.Point, { total: number }>[]): number {
  return features.reduce((m, f) => Math.max(m, f.properties.total), 0);
}

/**
 * Coordinates as public.location stores them: numeric(9,6), six decimals (about 0.1 m).
 */
export function roundCoordinate(value: number): number {
  return Math.round(value * 1e6) / 1e6;
}

/**
 * Where the location picker opens (z2qt08): at the location's own point when its latitude
 * and longitude are valid numbers, else at its region's centre, else over the whole map.
 * `fromLocation` says the pin starts on the stored point.
 */
export function pickerStart(
  latitude: string | null | undefined,
  longitude: string | null | undefined,
  regionCentre: { latitude: number | null; longitude: number | null } | null
): { center: [number, number]; zoom: number; fromLocation: boolean } {
  const lat = Number(latitude);
  const lon = Number(longitude);
  if (latitude && longitude && Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
    return { center: [lon, lat], zoom: 14, fromLocation: true };
  }
  if (regionCentre?.latitude != null && regionCentre.longitude != null) {
    return { center: [Number(regionCentre.longitude), Number(regionCentre.latitude)], zoom: 9, fromLocation: false };
  }
  return { center: [10, 62], zoom: 4, fromLocation: false };
}

/** A unit of the hierarchy as the Links map needs it: its kind, name, link and physical locations. */
type HierarchyRegion = { name: string; path: string; center_latitude: number | null; center_longitude: number | null };
type HierarchyLocation = { type: string; latitude: number | null; longitude: number | null; region?: HierarchyRegion | null };
type HierarchyUnit = { id: number; name: string; location?: HierarchyLocation[] };
export interface LinksHierarchy {
  enterprise: {
    id: number;
    short_name?: string | null;
    legal_unit?: (HierarchyUnit & { establishment?: HierarchyUnit[] })[];
    establishment?: HierarchyUnit[];
  };
}

export interface UnitPointProperties {
  unit_type: MapUnitType;
  id: number;
  name: string;
  href: string;
  /** The unit whose page this is. */
  current: boolean;
  /** "point": the unit's own coordinates; "region": its region's centre, the unit is somewhere there. */
  placed: "point" | "region";
  /** The region of a unit placed at its region's centre. */
  region_name?: string;
}

const UNIT_PATH: Record<MapUnitType, string> = {
  enterprise: "enterprises",
  legal_unit: "legal-units",
  establishment: "establishments",
};

/**
 * The legal units and establishments of the page's enterprise on the map (z2qt08, owner
 * 2026-11-23): at their physical location's coordinates, or, without them, at their region's
 * centre, which says the unit is somewhere in that region. A unit with neither has no place
 * and is only counted. The enterprise has no location of its own: it is where its primary
 * unit is, so it is not drawn as a point of its own.
 */
export function linksUnitPoints(
  hierarchy: LinksHierarchy,
  current: { unitType: MapUnitType; id: number }
): {
  features: GeoJSON.FeatureCollection<GeoJSON.Point, UnitPointProperties>;
  total: number;
  atPoint: number;
  atRegion: number;
} {
  const units: { unit_type: MapUnitType; unit: HierarchyUnit }[] = [];
  for (const lu of hierarchy.enterprise.legal_unit ?? []) {
    units.push({ unit_type: "legal_unit", unit: lu });
    for (const es of lu.establishment ?? []) units.push({ unit_type: "establishment", unit: es });
  }
  for (const es of hierarchy.enterprise.establishment ?? []) units.push({ unit_type: "establishment", unit: es });

  const features: GeoJSON.Feature<GeoJSON.Point, UnitPointProperties>[] = [];
  let atPoint = 0;
  let atRegion = 0;
  for (const { unit_type, unit } of units) {
    const physical = (unit.location ?? []).find((l) => l.type === "physical");
    const base = {
      unit_type,
      id: unit.id,
      name: unit.name,
      href: `/${UNIT_PATH[unit_type]}/${unit.id}`,
      current: unit_type === current.unitType && unit.id === current.id,
    };
    if (physical?.latitude != null && physical.longitude != null) {
      atPoint += 1;
      features.push({
        type: "Feature",
        geometry: { type: "Point", coordinates: [Number(physical.longitude), Number(physical.latitude)] },
        properties: { ...base, placed: "point" },
      });
      continue;
    }
    const region = physical?.region;
    if (region?.center_latitude != null && region.center_longitude != null) {
      atRegion += 1;
      features.push({
        type: "Feature",
        geometry: { type: "Point", coordinates: [Number(region.center_longitude), Number(region.center_latitude)] },
        properties: { ...base, placed: "region", region_name: region.name },
      });
    }
  }
  return { features: { type: "FeatureCollection", features }, total: units.length, atPoint, atRegion };
}
