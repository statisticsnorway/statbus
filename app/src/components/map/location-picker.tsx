"use client";

import { useCallback, useRef, useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { LocateFixed, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { UnitMap, cssColour } from "./unit-map";
import { locationView, pickerStart, roundCoordinate } from "./map-data";
import {
  drawLocation,
  frame,
  PointCard,
  type PointValues,
  REGION_DOT,
  REGION_SHOWN_BOX,
  showRegion,
} from "./location-map";
import { searchPlaces, type PlaceMatch } from "./region-placer";

/** The physical address the form holds, read when the map opens. */
export interface AddressForLookup {
  /** One line, as a person writes it ("Eivensstuen 2, 2022 Gjerdrum"). */
  line: string;
  /** The country's ISO 3166 alpha-2 code, to keep OpenStreetMap's matches in that country. */
  countryCode: string | null;
  /** The region's name, shown beside the address. */
  regionName: string | null;
}

export type { PointValues };

/**
 * A physical location on a large map (z2qt08, owner 2026-11-24), opened from the location field's
 * preview. Shown: the stored point, or the region's centre when there is none, read only. Edited:
 * the unit's address stands above the map so the point can be judged against it; "Look up the
 * address" asks OpenStreetMap for it and puts the pin on the first match, the others listed; a
 * search field finds any place by name. A click or a drag moves the pin. "Enter coordinates" opens
 * the latitude, longitude and altitude as numbers, for a point known from elsewhere (a GPS, another
 * register); typing there moves the pin. "Use this point" hands the values back to the field. Each
 * lookup is one person's search (OpenStreetMap's usage policy); geocoding many units at once is
 * its own workflow (nq8zqt).
 */
export function LocationPicker({
  open,
  editing,
  values,
  regionCentre,
  address,
  onClose,
  onUse,
}: {
  open: boolean;
  /** Whether the point can be moved; else the map only shows it. */
  editing: boolean;
  values: PointValues;
  regionCentre: { latitude: number | null; longitude: number | null } | null;
  /** The address the form holds now, read when the map opens. */
  address: () => AddressForLookup;
  onClose: () => void;
  onUse: (values: PointValues) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-4xl">
        {/* Mounted per opening, so each starts from the field's values and the form's address then. */}
        {open && (
          <PickerBody
            editing={editing}
            values={values}
            regionCentre={regionCentre}
            address={address}
            onClose={onClose}
            onUse={onUse}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function PickerBody({
  editing: isEditing,
  values,
  regionCentre,
  address,
  onClose,
  onUse,
}: {
  editing: boolean;
  values: PointValues;
  regionCentre: { latitude: number | null; longitude: number | null } | null;
  address: () => AddressForLookup;
  onClose: () => void;
  onUse: (values: PointValues) => void;
}) {
  const [draft, setDraft] = useState<PointValues>(values);
  const [shownAddress] = useState<AddressForLookup>(address);
  const [start] = useState(() =>
    locationView(values.latitude, values.longitude, regionCentre)
  );
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<PlaceMatch[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [regionShown, setRegionShown] = useState(false);
  const hideRegionRef = useRef<(() => void) | null>(null);
  const markerRef = useRef<Marker | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);

  const hasPoint = pickerStart(
    draft.latitude,
    draft.longitude,
    null
  ).fromLocation;

  // Puts the pin at a place and the place into the draft; a looked-up place also moves the map.
  const place = useCallback((lngLat: [number, number], fly: boolean) => {
    const map = mapRef.current;
    const marker = markerRef.current;
    const lng = roundCoordinate(lngLat[0]);
    const lat = roundCoordinate(lngLat[1]);
    setDraft((d) => ({ ...d, latitude: String(lat), longitude: String(lng) }));
    if (!map || !marker) return;
    marker.setLngLat([lng, lat]).addTo(map);
    if (fly)
      map.easeTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 15) });
  }, []);

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      // The dialog opens with a zoom animation, so the map measured its box mid-way; measure
      // again once it has settled, or markers are placed against the wrong size.
      window.setTimeout(() => {
        map.resize();
        frame(map, start, false);
      }, 250);
      void drawLocation(map, start, {
        draggable: isEditing,
      }).then((marker) => {
        markerRef.current = marker;
        if (!isEditing) return;
        map.on("click", (e) => place([e.lngLat.lng, e.lngLat.lat], false));
        marker.on("dragend", () => {
          const { lng, lat } = marker.getLngLat();
          place([lng, lat], false);
        });
      });
    },
    [place, start, isEditing]
  );

  // "Region" shows the region's centre with the point; a second click goes back to the point.
  const toggleRegion = async () => {
    const map = mapRef.current;
    if (!map || !shownAddress.regionName) return;
    const view = locationView(draft.latitude, draft.longitude, regionCentre);
    if (hideRegionRef.current) {
      hideRegionRef.current();
      hideRegionRef.current = null;
      setRegionShown(false);
      frame(map, view, false);
      return;
    }
    hideRegionRef.current = await showRegion(
      map,
      view,
      shownAddress.regionName
    );
    setRegionShown(true);
  };

  // Brings the point (with the region, when shown) back into view.
  const recentre = () => {
    const map = mapRef.current;
    if (!map) return;
    frame(
      map,
      locationView(draft.latitude, draft.longitude, regionCentre),
      regionShown
    );
  };

  // A coordinate typed by hand moves the pin once it is a valid point.
  const typeCoordinate = (field: keyof PointValues, text: string) => {
    const next = { ...draft, [field]: text };
    setDraft(next);
    const at = pickerStart(next.latitude, next.longitude, null);
    if (at.fromLocation && field !== "altitude") {
      const map = mapRef.current;
      markerRef.current?.setLngLat(at.center).addTo(map!);
      map?.easeTo({ center: at.center });
    }
  };

  // One search of OpenStreetMap; the first match takes the pin when it is the address lookup.
  const lookUp = async (text: string, pinFirst: boolean) => {
    if (!text.trim()) return;
    setSearching(true);
    setError(null);
    try {
      const found = await searchPlaces(text, shownAddress?.countryCode ?? null);
      setMatches(found);
      if (pinFirst && found[0])
        place([found[0].longitude, found[0].latitude], true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSearching(false);
    }
  };

  return (
    <>
      <DialogHeader>
        <DialogTitle>
          {isEditing
            ? "Edit the location on the map"
            : "The location on the map"}
        </DialogTitle>
        <DialogDescription className={isEditing ? undefined : "sr-only"}>
          {isEditing
            ? "Look up the address, or find a place, then click the map or drag the pin to the unit's place."
            : "The unit's point and its region's centre."}
        </DialogDescription>
      </DialogHeader>
      {/* The address stays in view while the point is judged; the region stands at its right as
          its own small box, a click showing it on the map (owner 2026-11-24). */}
      <div
        className="flex items-stretch gap-2 text-sm"
        data-location-picker-address=""
      >
        <div className="flex-1 rounded border bg-gray-50 px-3 py-2">
          <span className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Address
          </span>
          <p>
            {shownAddress.line || (
              <span className="text-gray-500">No address</span>
            )}
          </p>
        </div>
        {/* The point between address and region (owner 2026-11-24). */}
        <PointCard
          values={draft}
          view={locationView(draft.latitude, draft.longitude, regionCentre)}
          onType={isEditing ? typeCoordinate : undefined}
          onRestore={(previous) => {
            setDraft(previous);
            const map = mapRef.current;
            const at = locationView(
              previous.latitude,
              previous.longitude,
              regionCentre
            );
            if (!map) return;
            if (at.point) markerRef.current?.setLngLat(at.point).addTo(map);
            else markerRef.current?.remove();
            frame(map, at, regionShown);
          }}
        />
        {shownAddress.regionName && (
          <button
            type="button"
            className={`rounded px-3 py-2 text-left ${regionShown ? REGION_SHOWN_BOX : "border-2 border-gray-200 bg-gray-50 hover:bg-gray-100"} disabled:cursor-default disabled:hover:bg-gray-50`}
            onClick={() => void toggleRegion()}
            disabled={regionCentre?.latitude == null}
            aria-pressed={regionShown}
            title={
              regionShown ? "Back to the point" : "Show the region on the map"
            }
            data-location-picker-region=""
          >
            <span className="block text-xs font-medium uppercase tracking-wide text-gray-500">
              Region
            </span>
            <span className="flex items-center gap-1.5">
              {/* The same dot as the region's mark on the map, so the two read as one. */}
              <span className={REGION_DOT} aria-hidden />
              <span className={regionShown ? "font-semibold" : undefined}>
                {shownAddress.regionName}
              </span>
            </span>
          </button>
        )}
      </div>
      {isEditing && (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              size="sm"
              onClick={() => lookUp(shownAddress?.line ?? "", true)}
              disabled={searching || !shownAddress?.line}
              data-location-picker-lookup=""
            >
              <Search className="mr-1.5 h-4 w-4" />
              Look up the address
            </Button>
            <form
              className="relative min-w-60 flex-1"
              onSubmit={(e) => {
                e.preventDefault();
                void lookUp(query, false);
              }}
            >
              <Search
                className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400"
                aria-hidden
              />
              <Input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Find a place, e.g. Gjerdrum, and press Enter"
                aria-label="Find a place on OpenStreetMap"
                className="h-9 pl-7 pr-7"
                data-location-picker-find=""
              />
              {query && (
                <button
                  type="button"
                  className="absolute right-1 top-1/2 -translate-y-1/2 rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-900"
                  aria-label="Clear the place search"
                  onClick={() => {
                    setQuery("");
                    setMatches(null);
                  }}
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </form>
          </div>
          {searching && (
            <p className="text-sm text-gray-500">Asking OpenStreetMap…</p>
          )}
          {error && <p className="text-sm text-red-700">{error}</p>}
          {matches && (
            <ul
              className="max-h-32 space-y-0.5 overflow-y-auto text-sm"
              data-location-picker-matches=""
            >
              {matches.length === 0 && (
                <li className="text-gray-500">
                  OpenStreetMap found nothing; try fewer words or a place name.
                </li>
              )}
              {matches.map((m) => (
                <li key={`${m.latitude},${m.longitude},${m.label}`}>
                  <button
                    type="button"
                    className="w-full rounded px-1.5 py-0.5 text-left hover:bg-gray-100"
                    onClick={() => place([m.longitude, m.latitude], true)}
                  >
                    <span>{m.label}</span>
                    <span className="ml-1.5 text-xs text-gray-500">
                      {m.kind}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      <div className="relative h-[24rem] overflow-hidden rounded border">
        <UnitMap onReady={onReady} className="absolute inset-0" />
        {/* Back to the point after panning or zooming away (owner 2026-11-24). */}
        <button
          type="button"
          className="absolute left-[10px] top-[84px] flex h-[29px] w-[29px] items-center justify-center rounded bg-white text-gray-800 shadow-[0_0_0_2px_rgba(0,0,0,0.1)] hover:bg-gray-100"
          onClick={recentre}
          title="Back to the point"
          aria-label="Back to the point"
          data-location-picker-recentre=""
        >
          <LocateFixed className="h-4 w-4" />
        </button>
      </div>
      <DialogFooter className="items-center gap-3">
        <div className="flex gap-2">
          {isEditing ? (
            <>
              <Button type="button" variant="outline" onClick={onClose}>
                Cancel
              </Button>
              <Button
                type="button"
                onClick={() => onUse(draft)}
                data-location-picker-use=""
              >
                Use this point
              </Button>
            </>
          ) : (
            <Button type="button" variant="outline" onClick={onClose}>
              Close
            </Button>
          )}
        </div>
      </DialogFooter>
    </>
  );
}
