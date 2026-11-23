"use client";

import { useCallback, useRef, useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { MapPin, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { UnitMap, cssColour } from "./unit-map";
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
 * bulk lookups), which is what this is: one search per click by an admin placing a region
 * (owner 2026-11-23, z2qt08). Geocoding units in bulk is its own workflow (nq8zqt).
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

/**
 * "Place on map" for a region: the search box starts with the region's name, its matches
 * from OpenStreetMap are listed, and choosing one puts the pin there for the person to judge
 * on the map; a click or a drag moves it. Save stores the pin as the region's centre.
 */
export function RegionPlacer({
  region,
  countryCode,
  onSave,
}: {
  region: { name: string; path: string; latitude: number | null; longitude: number | null };
  countryCode: string | null;
  onSave: (point: { latitude: number; longitude: number }) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState(region.name);
  const [matches, setMatches] = useState<PlaceMatch[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [point, setPoint] = useState<[number, number] | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const markerRef = useRef<Marker | null>(null);

  const place = useCallback((lngLat: [number, number], fly: boolean) => {
    const map = mapRef.current;
    const marker = markerRef.current;
    if (!map || !marker) return;
    marker.setLngLat(lngLat).addTo(map);
    setPoint([roundCoordinate(lngLat[0]), roundCoordinate(lngLat[1])]);
    if (fly) map.easeTo({ center: lngLat, zoom: Math.max(map.getZoom(), 8) });
  }, []);

  const search = useCallback(
    async (text: string) => {
      if (!text.trim()) return;
      setSearching(true);
      setError(null);
      try {
        setMatches(await searchPlaces(text, countryCode));
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        setMatches(null);
      } finally {
        setSearching(false);
      }
    },
    [countryCode]
  );

  const begin = () => {
    setQuery(region.name);
    setMatches(null);
    setError(null);
    setPoint(region.latitude != null && region.longitude != null ? [region.longitude, region.latitude] : null);
    setOpen(true);
    void search(region.name);
  };

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      const start: [number, number] | null =
        region.latitude != null && region.longitude != null ? [region.longitude, region.latitude] : null;
      // The dialog opens with a zoom animation; measure the map again once it has settled.
      const settle = () => {
        map.resize();
        if (start) map.jumpTo({ center: start, zoom: 8 });
      };
      settle();
      window.setTimeout(settle, 250);
      import("maplibre-gl").then(({ Marker }) => {
        const marker = new Marker({ draggable: true, color: cssColour("--color-legal_unit-600") || undefined });
        markerRef.current = marker;
        if (start) marker.setLngLat(start).addTo(map);
        map.on("click", (e) => place([e.lngLat.lng, e.lngLat.lat], false));
        marker.on("dragend", () => {
          const { lng, lat } = marker.getLngLat();
          place([lng, lat], false);
        });
      });
    },
    [region.latitude, region.longitude, place]
  );

  const save = async () => {
    if (!point) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({ latitude: point[1], longitude: point[0] });
      setOpen(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Button type="button" variant="outline" size="sm" onClick={begin} data-region-placer={region.path}>
        <MapPin className="mr-1.5 h-4 w-4" />
        Place on map
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-5xl">
          <DialogHeader>
            <DialogTitle>
              Place {region.name} <span className="font-normal text-gray-500">{region.path}</span>
            </DialogTitle>
            <DialogDescription>
              Choose a match from OpenStreetMap and check it on the map, or click the map or drag the pin. Save stores the
              point as the region&apos;s centre.
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-[16rem_1fr] gap-3">
            <div className="space-y-2 text-sm">
              <form
                className="flex gap-1"
                onSubmit={(e) => {
                  e.preventDefault();
                  void search(query);
                }}
              >
                <Input value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Place name" data-region-placer-query="" />
                <Button type="submit" variant="outline" size="icon" disabled={searching} aria-label="Search OpenStreetMap">
                  <Search className="h-4 w-4" />
                </Button>
              </form>
              {searching && <p className="text-gray-500">Searching OpenStreetMap…</p>}
              {matches && matches.length === 0 && (
                <p className="text-gray-600">No match. Try another name, or place the pin by hand.</p>
              )}
              {matches && matches.length > 0 && (
                <ul className="space-y-1" data-region-placer-matches="">
                  {matches.map((m) => (
                    <li key={`${m.latitude},${m.longitude},${m.label}`}>
                      <button
                        type="button"
                        className="w-full rounded border px-2 py-1 text-left hover:bg-gray-50"
                        onClick={() => place([m.longitude, m.latitude], true)}
                      >
                        <span className="block font-medium">{m.name}</span>
                        <span className="block text-xs text-gray-500">
                          {m.kind}: {m.label}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
              <p className="text-xs text-gray-500">Search by © OpenStreetMap contributors.</p>
            </div>
            <div className="relative h-[28rem] overflow-hidden rounded border">
              {open && <UnitMap onReady={onReady} className="absolute inset-0" />}
            </div>
          </div>
          <DialogFooter className="items-center gap-3 sm:justify-between">
            <span className="text-sm tabular-nums text-gray-600" data-region-placer-point="">
              {error ? <span className="text-red-700">{error}</span> : point ? `Latitude ${point[1]}, longitude ${point[0]}` : "No point yet"}
            </span>
            <div className="flex gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="button" onClick={save} disabled={!point || saving} data-region-placer-save="">
                Save
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
