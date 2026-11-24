"use client";

import { useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { MapPin, Pencil } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cssColour } from "./unit-map";
import { type locationView } from "./map-data";

type View = ReturnType<typeof locationView>;

/**
 * The region's look, shared by its box above the map and its mark on the map so the two read as
 * one (owner 2026-11-24): a dark-ringed dot, and when shown a dark outline round a white box with
 * the name in bold.
 */
export const REGION_DOT =
  "block h-3 w-3 shrink-0 rounded-full border-2 border-gray-800 bg-white";
export const REGION_SHOWN_BOX =
  "border-2 border-gray-800 bg-white text-gray-900";

/**
 * Draws a location's point on a map as a pin and frames it (z2qt08). Returns the pin, placed only
 * when there is a point, for the editor to move. With no point the map stands at the region's
 * centre, else over the country.
 */
export async function drawLocation(
  map: MapLibreMap,
  view: View,
  options: { draggable: boolean }
): Promise<Marker> {
  const { Marker } = await import("maplibre-gl");
  const pin = new Marker({
    draggable: options.draggable,
    color: cssColour("--color-legal_unit-600") || undefined,
  });
  if (view.point) pin.setLngLat(view.point).addTo(map);
  frame(map, view, false);
  return pin;
}

/**
 * Marks the region's centre with its name, on request (owner 2026-11-24: "Region: Gjerdrum", click,
 * and the map shows it), and frames it with the point. A region is known by its centre only, so
 * the mark is a labelled dot, not an outline. Returns a function that takes the mark away again.
 */
export async function showRegion(
  map: MapLibreMap,
  view: View,
  regionName: string
): Promise<() => void> {
  if (!view.region) return () => {};
  const { Marker } = await import("maplibre-gl");
  const mark = document.createElement("div");
  mark.className = "pointer-events-none flex items-center gap-1.5";
  mark.dataset.regionCentre = "";
  const dot = document.createElement("span");
  dot.className = REGION_DOT;
  const label = document.createElement("span");
  label.className = `whitespace-nowrap rounded px-1.5 py-0.5 text-xs font-semibold shadow-sm ${REGION_SHOWN_BOX}`;
  label.textContent = regionName;
  mark.append(dot, label);
  // Anchored on the dot, the name reading to its right.
  const marker = new Marker({ element: mark, anchor: "left", offset: [-6, 0] })
    .setLngLat(view.region)
    .addTo(map);
  frame(map, view, true);
  return () => marker.remove();
}

/**
 * Puts the location in sight: the point at street level, or with `withRegion` the point and its
 * region's centre together. With no point it stands at the region's centre.
 */
export function frame(map: MapLibreMap, view: View, withRegion: boolean) {
  if (withRegion && view.bounds) {
    map.fitBounds(view.bounds, { padding: 64, maxZoom: 13, duration: 600 });
  } else {
    map.jumpTo({ center: view.center, zoom: view.zoom });
  }
}

/** A location's coordinates as the form keeps them: text, empty when not set. */
export interface PointValues {
  latitude: string;
  longitude: string;
  altitude: string;
}

/**
 * The Point card (owner 2026-11-24, "I really like" it): the coordinates under a pin mark in the
 * pin's colour, the same card beside the form's small map and in the map dialog. With `onType`
 * it has a pencil that turns the numbers into inputs; each keystroke goes to `onType`, so a map
 * can move its pin as the number is typed. Enter folds the inputs back.
 */
export function PointCard({
  values,
  view,
  onType,
  onRestore,
}: {
  values: PointValues;
  view: View;
  onType?: (field: keyof PointValues, text: string) => void;
  onRestore?: (values: PointValues) => void;
}) {
  const [typing, setTyping] = useState(false);
  const [original, setOriginal] = useState(values);
  const editable = onType !== undefined;
  const open = editable && typing;
  return (
    <div
      className={`rounded border-2 px-3 py-2 ${open ? "border-gray-800 bg-white" : "border-gray-200 bg-gray-50"}`}
      data-location-point=""
    >
      <span className="flex items-center gap-1 text-xs font-medium uppercase tracking-wide text-gray-500">
        <MapPin
          className="h-3.5 w-3.5"
          style={{ color: "var(--color-legal_unit-600)" }}
          aria-hidden
        />
        Point
        {editable && open && (
          <button
            type="button"
            className="ml-auto rounded px-1 text-xs normal-case text-gray-600 hover:bg-gray-200"
            onClick={() => {
              onRestore?.(original);
              setTyping(false);
            }}
            aria-label="Cancel coordinate changes"
          >
            Cancel
          </button>
        )}
        {editable && !open && (
          <button
            type="button"
            className="ml-auto rounded p-0.5 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
            onClick={() => {
              setOriginal({ ...values });
              setTyping(true);
            }}
            title="Edit the coordinates"
            aria-label="Edit the coordinates"
            data-location-edit-coordinates=""
          >
            <Pencil className="h-3.5 w-3.5" />
          </button>
        )}
      </span>
      {open ? (
        <div className="mt-1 grid grid-cols-[auto_8rem] items-center gap-x-2 gap-y-1">
          {(["latitude", "longitude", "altitude"] as const).map((f) => (
            <Label key={f} className="contents">
              <span className="text-xs capitalize text-gray-600">{f}</span>
              <Input
                value={values[f]}
                onChange={(e) => onType(f, e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    setTyping(false);
                  }
                }}
                placeholder={f === "altitude" ? "metres" : undefined}
                inputMode="decimal"
                autoComplete="off"
                autoFocus={f === "latitude"}
                className="h-7 bg-white px-2 text-sm tabular-nums"
              />
            </Label>
          ))}
        </div>
      ) : (
        <Coordinates
          latitude={values.latitude}
          longitude={values.longitude}
          altitude={values.altitude}
          view={view}
        />
      )}
    </div>
  );
}

/**
 * A location's coordinates, each named (owner 2026-11-24: which number is which), at the six
 * decimals location stores.
 */
export function Coordinates({
  latitude,
  longitude,
  altitude,
  view,
}: {
  latitude: string;
  longitude: string;
  altitude: string;
  view: View;
}) {
  const shown = (v: string) => Number(v).toFixed(6);
  const unset = <span className="text-gray-400">not set</span>;
  // Each number named on its own line, a narrow column beside the map; altitude is always listed,
  // "not set" when missing, so its absence reads as a fact rather than an omission (owner
  // 2026-11-24).
  return (
    <dl
      className="grid grid-cols-[auto_auto] justify-start gap-x-3 text-sm tabular-nums"
      data-location-coordinates=""
    >
      <dt className="text-gray-500">Latitude</dt>
      <dd>{view.point ? shown(latitude) : unset}</dd>
      <dt className="text-gray-500">Longitude</dt>
      <dd>{view.point ? shown(longitude) : unset}</dd>
      <dt className="text-gray-500">Altitude</dt>
      <dd>{altitude ? `${altitude} m` : unset}</dd>
    </dl>
  );
}
