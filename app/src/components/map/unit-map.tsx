"use client";

import { useRef, useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { BASEMAP_STYLE_URL } from "./basemap";

/**
 * A MapLibre map on the StatBus base map, for any of the map pages (z2qt08). MapLibre is
 * loaded on first use only (about 220 KB gzip), as the reports load Highcharts. `onReady`
 * runs once the style has loaded, with the map, to add the page's sources and layers; the
 * page keeps the map to update its data.
 */
export function UnitMap({
  onReady,
  className,
  initialBounds,
}: {
  onReady: (map: MapLibreMap) => void;
  className?: string;
  initialBounds?: [number, number, number, number] | null;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);
  // Read once at mount: the page's later changes go through the map it got in onReady.
  const onReadyRef = useRef(onReady);
  const boundsRef = useRef(initialBounds);

  useGuardedEffect(
    () => {
      let map: MapLibreMap | null = null;
      let cancelled = false;
      import("maplibre-gl")
        .then(({ Map, NavigationControl, AttributionControl, setWorkerUrl }) => {
          if (cancelled || !containerRef.current) return;
          // MapLibre finds its worker next to its own module (import.meta.url), which after
          // bundling is a Next chunk, not maplibre-gl/dist; the bundler emits the worker as an
          // asset at this URL instead.
          setWorkerUrl(new URL("maplibre-gl/dist/maplibre-gl-worker.mjs", import.meta.url).href);
          const bounds = boundsRef.current;
          map = new Map({
            container: containerRef.current,
            style: BASEMAP_STYLE_URL,
            ...(bounds ? { bounds, fitBoundsOptions: { padding: 40 } } : { center: [10, 62], zoom: 4 }),
            attributionControl: false,
          });
          map.addControl(new NavigationControl({ showCompass: false }), "top-left");
          map.addControl(new AttributionControl({ compact: true }), "bottom-right");
          map.on("error", (e) => setError(e.error?.message ?? "The map could not load."));
          map.once("load", () => {
            if (cancelled || !map) return;
            // Development only: driven browser checks reach the map to project and move it.
            if (process.env.NODE_ENV === "development") (window as unknown as { __statbusMap?: MapLibreMap }).__statbusMap = map;
            onReadyRef.current(map);
          });
        })
        .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)));
      return () => {
        cancelled = true;
        map?.remove();
      };
    },
    [],
    "UnitMap:create"
  );

  return (
    <div className={className} data-unit-map="">
      <div ref={containerRef} className="h-full w-full" />
      {error && (
        <p className="absolute left-1/2 top-4 -translate-x-1/2 rounded bg-red-50 px-3 py-2 text-sm text-red-700 shadow" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

/** A CSS variable's colour on this page (the unit-type colours of globals.css), for MapLibre paint. */
export function cssColour(variable: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(variable).trim();
}
