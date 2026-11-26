/**
 * Place search on OpenStreetMap, shared by the location dialog for units and regions
 * (location-picker.tsx).
 */
import { roundCoordinate } from "./map-data";

/** One place OpenStreetMap's Nominatim found for a name. */
export interface PlaceMatch {
  name: string;
  /** The place's full name with its surroundings ("Bjørnøya naturreservat, Norge"). */
  label: string;
  kind: string;
  latitude: number;
  longitude: number;
}

/**
 * Asks OpenStreetMap's Nominatim for places by name, in the installation's country when
 * known. Nominatim's usage policy allows a person's own searches (at most one a second, no
 * bulk lookups), which is what this is: one search per click by a person placing a unit or a
 * region (owner 2026-11-23, z2qt08). Geocoding in bulk is its own workflow (nq8zqt).
 */
export async function searchPlaces(query: string, countryCode: string | null): Promise<PlaceMatch[]> {
  const params = new URLSearchParams({ q: query, format: "jsonv2", limit: "5" });
  if (countryCode) params.set("countrycodes", countryCode.toLowerCase());
  const response = await fetch(`https://nominatim.openstreetmap.org/search?${params}`, {
    headers: { "Accept-Language": "en" },
  });
  if (!response.ok) throw new Error(`OpenStreetMap search failed (${response.status})`);
  const results = (await response.json()) as { name: string; display_name: string; type: string; lat: string; lon: string }[];
  return results.map((r) => ({
    name: r.name || r.display_name,
    label: r.display_name,
    kind: r.type.replace(/_/g, " "),
    latitude: roundCoordinate(Number(r.lat)),
    longitude: roundCoordinate(Number(r.lon)),
  }));
}
