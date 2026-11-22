"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "./unit-map";
import { UnitTypeLegend } from "./unit-type-legend";
import { BASEMAP_FONT } from "./basemap";
import { featureBounds, linksUnitPoints, type LinksHierarchy, type MapUnitType, type UnitPointProperties } from "./map-data";

/**
 * A unit's Links page map (z2qt08): every legal unit and establishment of its enterprise at
 * its physical location, in the app's unit-type colours, the page's own unit ringed. The
 * units come from the hierarchy the page already reads, so the map adds no request. Says how
 * many units have no coordinates, and plainly when none have.
 */
export function LinksMap({ unitId, unitType }: { unitId: string; unitType: "enterprise" | "legal_unit" | "establishment" }) {
  const { hierarchy } = useStatisticalUnitHierarchy(unitId, unitType);
  const [unitTypes, setUnitTypes] = useState<MapUnitType[]>(["legal_unit", "establishment"]);
  const [picked, setPicked] = useState<UnitPointProperties | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);

  const points = useMemo(
    () => (hierarchy?.enterprise ? linksUnitPoints(hierarchy as unknown as LinksHierarchy, { unitType, id: Number(unitId) }) : null),
    [hierarchy, unitType, unitId]
  );
  const totals = useMemo(() => {
    const t: Record<MapUnitType, number> = { enterprise: 0, legal_unit: 0, establishment: 0 };
    for (const f of points?.features.features ?? []) t[f.properties.unit_type] += 1;
    return t;
  }, [points]);
  const shown = useMemo(
    () => ({
      type: "FeatureCollection" as const,
      features: (points?.features.features ?? []).filter((f) => unitTypes.includes(f.properties.unit_type)),
    }),
    [points, unitTypes]
  );

  const onReady = useCallback((map: MapLibreMap) => {
    mapRef.current = map;
    map.addSource("units", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addLayer({
      id: "unit-points",
      type: "circle",
      source: "units",
      paint: {
        "circle-color": [
          "match",
          ["get", "unit_type"],
          "legal_unit",
          cssColour("--color-legal_unit-500"),
          "establishment",
          cssColour("--color-establishment-500"),
          cssColour("--color-enterprise-500"),
        ],
        "circle-radius": ["case", ["get", "current"], 9, 6],
        "circle-stroke-color": ["case", ["get", "current"], "#111827", "#ffffff"],
        "circle-stroke-width": ["case", ["get", "current"], 3, 1.5],
      },
    });
    map.addLayer({
      id: "unit-labels",
      type: "symbol",
      source: "units",
      layout: {
        "text-field": ["get", "name"],
        "text-font": BASEMAP_FONT,
        "text-size": 11,
        "text-offset": [0, 1.1],
        "text-anchor": "top",
        "text-optional": true,
      },
      paint: { "text-color": "#1f2937", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
    });
    map.on("mouseenter", "unit-points", () => (map.getCanvas().style.cursor = "pointer"));
    map.on("mouseleave", "unit-points", () => (map.getCanvas().style.cursor = ""));
    map.on("click", "unit-points", (e: MapLayerMouseEvent) => {
      const f = e.features?.[0];
      if (f) setPicked(f.properties as UnitPointProperties);
    });
    setMapReady(true);
  }, []);

  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("units") as GeoJSONSource | undefined)?.setData(shown);
      const bounds = featureBounds(shown.features);
      // Labels hang below each point, so the bottom gets room for one.
      if (bounds) map.fitBounds(bounds, { padding: { top: 40, left: 50, right: 50, bottom: 70 }, maxZoom: 14, duration: 0 });
    },
    [shown, mapReady],
    "LinksMap:setData"
  );

  if (!points) return null;
  const placed = points.features.features.length;
  return (
    <section className="mb-6 space-y-2" data-links-map="">
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-medium">Map</h2>
        <p className="text-xs text-gray-600" data-links-map-placed="">
          {placed === 0
            ? `None of the ${points.total} units of this enterprise has coordinates.`
            : `${placed} of ${points.total} units of this enterprise have coordinates.`}
        </p>
      </div>
      {placed > 0 && (
        <div className="flex h-80 overflow-hidden rounded-md border">
          <div className="relative min-w-0 flex-1">
            <UnitMap onReady={onReady} className="absolute inset-0" />
          </div>
          <aside className="w-56 shrink-0 space-y-3 overflow-y-auto border-l p-3 text-sm">
            <UnitTypeLegend selected={unitTypes} onChange={setUnitTypes} totals={totals} unitTypes={["legal_unit", "establishment"]} mixedSwatch={false} />
            {picked && (
              <p data-links-map-picked="">
                <Link className="font-medium underline underline-offset-2" href={picked.href}>
                  {picked.name}
                </Link>
                {picked.current && <span className="ml-1 text-xs text-gray-500">(this unit)</span>}
              </p>
            )}
          </aside>
        </div>
      )}
    </section>
  );
}
