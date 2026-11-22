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
