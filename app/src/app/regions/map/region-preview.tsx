"use client";

import { useState } from "react";
import Link from "next/link";
import { X } from "lucide-react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { Button } from "@/components/ui/button";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UNIT_TYPE_LABEL, UNIT_TYPE_SWATCH, selectedTotal, type MapUnitType } from "@/components/map/map-data";

/** The circle a single click previews: its selection, name, place and units per type. */
export interface PreviewTarget {
  /** The selection the circle stands for ("" the country, "country:SE", or a region path). */
  path: string;
  name: string;
  /** The region's code beside its name; none for a country. */
  code: string | null;
  coordinates: [number, number];
  counts: Record<MapUnitType, number>;
}

/**
 * A readable box over the Regions map for one circle (owner 2026-11-23, z2qt08: the map's own
 * labels are too small to read and hide where they overlap). A single click on a circle opens
 * it, a double click goes in. It stays beside its circle as the map moves; X, Escape or a click
 * on the map away from the circles closes it. The page mounts it keyed by the circle, so a new
 * circle starts at its own place.
 */
export function RegionPreview({
  map,
  target,
  unitTypes,
  canEnter,
  searchHref,
  onEnter,
  onClose,
}: {
  map: MapLibreMap;
  target: PreviewTarget;
  unitTypes: readonly MapUnitType[];
  canEnter: boolean;
  searchHref: string;
  onEnter: () => void;
  onClose: () => void;
}) {
  const [point, setPoint] = useState(() => map.project(target.coordinates));
  useGuardedEffect(
    () => {
      const follow = () => setPoint(map.project(target.coordinates));
      const closeOnEscape = (e: KeyboardEvent) => e.key === "Escape" && onClose();
      map.on("move", follow);
      document.addEventListener("keydown", closeOnEscape);
      return () => {
        map.off("move", follow);
        document.removeEventListener("keydown", closeOnEscape);
      };
    },
    [map, target, onClose],
    "RegionPreview:follow"
  );

  // Above the circle (the largest is 28 px in radius), or below it near the top of the map;
  // centred on it, but kept inside the map where the circle is near a side (the box is w-64).
  const below = point.y < 220;
  const half = 128 + 8;
  const width = map.getContainer().clientWidth;
  const left = Math.min(Math.max(point.x, half), Math.max(width - half, half));
  return (
    <div
      role="dialog"
      aria-label={target.name}
      className="absolute z-10 w-64 rounded border bg-white p-3 text-sm shadow-lg"
      style={{ left, top: point.y, transform: `translate(-50%, ${below ? "34px" : "calc(-100% - 34px)"})` }}
      data-regions-map-preview={target.path}
    >
      <button
        type="button"
        className="absolute right-1.5 top-1.5 rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
        aria-label="Close"
        onClick={onClose}
      >
        <X className="h-4 w-4" />
      </button>
      <p className="pr-6 text-base font-medium leading-tight">
        {target.name}
        {target.code && <span className="ml-1.5 text-xs font-normal text-gray-500">{target.code}</span>}
      </p>
      <ul className="mt-2 space-y-1">
        {unitTypes.map((t) => (
          <li key={t} className="flex items-center gap-2">
            <span className={`h-3 w-3 shrink-0 rounded-full ${UNIT_TYPE_SWATCH[t]}`} aria-hidden="true" />
            <span className="flex-1">{UNIT_TYPE_LABEL[t]}</span>
            <span className="tabular-nums">{target.counts[t].toLocaleString()}</span>
          </li>
        ))}
        {unitTypes.length > 1 && (
          <li className="flex justify-between border-t pt-1 font-medium">
            <span>Total</span>
            <span className="tabular-nums">{selectedTotal(target.counts, unitTypes).toLocaleString()}</span>
          </li>
        )}
      </ul>
      <div className="mt-3 flex gap-2">
        {canEnter && (
          <Button size="sm" className="flex-1" onClick={onEnter} data-regions-map-preview-enter="">
            Go in
          </Button>
        )}
        <Button asChild size="sm" variant="outline" className="flex-1">
          <Link href={searchHref}>View and download</Link>
        </Button>
      </div>
      {canEnter && <p className="mt-2 text-xs text-gray-500">A double click on a circle goes in at once.</p>}
    </div>
  );
}
