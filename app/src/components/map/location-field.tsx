"use client";

import { useCallback, useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { Expand, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap } from "./unit-map";
import { locationView } from "./map-data";
import { Coordinates, drawLocation } from "./location-map";
import {
  LocationPicker,
  type AddressForLookup,
  type PointValues,
} from "./location-picker";

/**
 * A physical location's place in its form (z2qt08, owner 2026-11-24: nobody types six-decimal
 * coordinates, so the map is the field). A small still map shows the point, and beside it the
 * latitude and longitude, each named. "Larger map" opens it large; while the location is edited,
 * "Edit on map" opens the editor (address, lookup, place search, coordinates). The values live in
 * hidden inputs named latitude, longitude and altitude, which the form's Save reads as it read
 * the boxes before.
 */
export function LocationField({
  isEditing,
  stored,
  regionCentre,
  address,
}: {
  isEditing: boolean;
  /** The stored values, as the form shows them (strings or numbers, possibly empty). */
  stored: { latitude: unknown; longitude: unknown; altitude: unknown };
  regionCentre: { latitude: number | null; longitude: number | null } | null;
  /** The address the form holds now, read when the editor opens. */
  address: () => AddressForLookup;
}) {
  const asText = (v: unknown) =>
    v === null || v === undefined ? "" : String(v);
  const [values, setValues] = useState<PointValues>({
    latitude: asText(stored.latitude),
    longitude: asText(stored.longitude),
    altitude: asText(stored.altitude),
  });
  // A new stored location (after Save, or Cancel of an edit) replaces what is shown.
  useGuardedEffect(
    () =>
      setValues({
        latitude: asText(stored.latitude),
        longitude: asText(stored.longitude),
        altitude: asText(stored.altitude),
      }),
    [stored.latitude, stored.longitude, stored.altitude, isEditing],
    "LocationField:syncStored"
  );
  const [open, setOpen] = useState<"show" | "edit" | null>(null);
  const view = locationView(values.latitude, values.longitude, regionCentre);

  return (
    <div className="space-y-2" data-location-field="">
      <span className="text-xs uppercase text-gray-600">Location</span>
      <input type="hidden" name="latitude" value={values.latitude} />
      <input type="hidden" name="longitude" value={values.longitude} />
      <input type="hidden" name="altitude" value={values.altitude} />
      <div className="flex flex-wrap items-start gap-4">
        <div className="relative h-40 w-full max-w-md overflow-hidden rounded border">
          <PreviewMap
            key={`${values.latitude},${values.longitude}:${view.region?.join(",")}`}
            view={view}
          />
          <button
            type="button"
            className="absolute right-2 top-2 flex items-center gap-1 rounded bg-white px-2 py-1 text-xs font-medium text-gray-700 shadow hover:bg-gray-100 hover:text-gray-900"
            onClick={() => setOpen(isEditing ? "edit" : "show")}
            data-location-expand=""
          >
            <Expand className="h-3.5 w-3.5" />
            Larger map
          </button>
        </div>
        <div className="space-y-3">
          <Coordinates
            latitude={values.latitude}
            longitude={values.longitude}
            altitude={values.altitude}
            view={view}
          />
          {isEditing && (
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => setOpen("edit")}
              data-location-open=""
            >
              <Pencil className="mr-1.5 h-4 w-4" />
              Edit on map
            </Button>
          )}
        </div>
      </div>
      <LocationPicker
        open={open !== null}
        editing={open === "edit"}
        values={values}
        regionCentre={regionCentre}
        address={address}
        onClose={() => setOpen(null)}
        onUse={(next) => {
          setValues(next);
          setOpen(null);
        }}
      />
    </div>
  );
}

/**
 * The small map: still (no pan, zoom or rotate), so it reads as a picture of the place; the
 * expand button opens the large one.
 */
function PreviewMap({ view }: { view: ReturnType<typeof locationView> }) {
  const onReady = useCallback(
    (map: MapLibreMap) => {
      for (const h of [
        map.dragPan,
        map.scrollZoom,
        map.boxZoom,
        map.dragRotate,
        map.keyboard,
        map.doubleClickZoom,
        map.touchZoomRotate,
      ])
        h.disable();
      // The preview has no zoom buttons: the large map has them.
      map.getContainer().querySelector(".maplibregl-ctrl-top-left")?.remove();
      void drawLocation(map, view, { draggable: false });
    },
    [view]
  );
  return (
    <UnitMap
      onReady={onReady}
      className="pointer-events-none absolute inset-0"
    />
  );
}
