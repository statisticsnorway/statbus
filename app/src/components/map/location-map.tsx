"use client";

import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { cssColour } from "./unit-map";
import { type locationView } from "./map-data";

type View = ReturnType<typeof locationView>;

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
  mark.className = "pointer-events-none flex items-center gap-1";
  mark.dataset.regionCentre = "";
  const dot = document.createElement("span");
  dot.className =
    "block h-3 w-3 rounded-full border-2 border-gray-800 bg-white/70";
  const label = document.createElement("span");
  label.className =
    "whitespace-nowrap rounded bg-white/90 px-1 text-xs font-semibold text-gray-900 shadow-sm";
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
  if (!view.point) {
    return (
      <p className="text-sm text-gray-600" data-location-coordinates="">
        No coordinates
      </p>
    );
  }
  const shown = (v: string) => Number(v).toFixed(6);
  // One line, each number named (owner 2026-11-24).
  return (
    <p
      className="flex flex-wrap gap-x-4 text-sm tabular-nums"
      data-location-coordinates=""
    >
      <span>
        <span className="text-gray-500">Latitude</span> {shown(latitude)}
      </span>
      <span>
        <span className="text-gray-500">Longitude</span> {shown(longitude)}
      </span>
      {altitude && (
        <span>
          <span className="text-gray-500">Altitude</span> {altitude} m
        </span>
      )}
    </p>
  );
}
