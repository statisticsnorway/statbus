"use client";

import { useCallback, useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { Maximize2, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "./unit-map";
import { pickerStart } from "./map-data";
import {
  LocationPicker,
  type AddressForLookup,
  type PointValues,
} from "./location-picker";

/**
 * A physical location's place, shown as a map instead of number boxes (owner 2026-11-24: nobody
 * types six-decimal coordinates; the map is the field, the numbers are secondary). A small map
 * shows the pin, or the region's centre when there is no point, with one line under it saying
 * which. "Show on map" opens it large; while the location is edited, "Edit on map" opens the
 * editor (address, lookup, place search, coordinates). The values live in hidden inputs named
 * latitude, longitude and altitude, which the form's Save reads as it read the boxes before.
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

  const start = pickerStart(values.latitude, values.longitude, regionCentre);
  const hasPoint = start.fromLocation;
  const line = hasPoint
    ? `${Number(values.latitude).toFixed(4)}, ${Number(values.longitude).toFixed(4)}${values.altitude ? `, ${values.altitude} m` : ""}`
    : regionCentre?.latitude != null
      ? "No point; the region's centre is shown"
      : "No point";

  return (
    <div className="space-y-2" data-location-field="">
      <span className="text-xs uppercase text-gray-600">Location</span>
      <input type="hidden" name="latitude" value={values.latitude} />
      <input type="hidden" name="longitude" value={values.longitude} />
      <input type="hidden" name="altitude" value={values.altitude} />
      <div className="flex flex-wrap items-start gap-3">
        <button
          type="button"
          className="relative h-40 w-full max-w-md overflow-hidden rounded border text-left focus:outline-none focus:ring-2 focus:ring-gray-400"
          onClick={() => setOpen(isEditing ? "edit" : "show")}
          title={isEditing ? "Edit on map" : "Show on map"}
          aria-label={
            isEditing
              ? "Edit the location on the map"
              : "Show the location on the map"
          }
          data-location-preview=""
        >
          <PreviewMap
            key={`${start.center.join(",")}:${hasPoint}`}
            center={start.center}
            zoom={hasPoint ? 13 : start.zoom}
            pin={hasPoint}
          />
        </button>
        <div className="space-y-2">
          <p
            className="text-sm tabular-nums text-gray-700"
            data-location-line=""
          >
            {line}
          </p>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => setOpen(isEditing ? "edit" : "show")}
            data-location-open=""
          >
            {isEditing ? (
              <Pencil className="mr-1.5 h-4 w-4" />
            ) : (
              <Maximize2 className="mr-1.5 h-4 w-4" />
            )}
            {isEditing ? "Edit on map" : "Show on map"}
          </Button>
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
 * The small map: still (no pan, zoom or rotate), so it reads as a picture of the place and a click
 * anywhere on it opens the large map.
 */
function PreviewMap({
  center,
  zoom,
  pin,
}: {
  center: [number, number];
  zoom: number;
  pin: boolean;
}) {
  const onReady = useCallback(
    (map: MapLibreMap) => {
      map.jumpTo({ center, zoom });
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
      if (!pin) return;
      import("maplibre-gl").then(({ Marker }) => {
        const marker: Marker = new Marker({
          color: cssColour("--color-legal_unit-600") || undefined,
        });
        marker.setLngLat(center).addTo(map);
      });
    },
    [center, zoom, pin]
  );
  return (
    <UnitMap
      onReady={onReady}
      className="pointer-events-none absolute inset-0"
    />
  );
}
