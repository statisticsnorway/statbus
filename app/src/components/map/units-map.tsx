"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "./unit-map";
import { UnitTypeLegend } from "./unit-type-legend";
import { BASEMAP_FONT } from "./basemap";
import { ViewControl } from "./view-control";
import { featureBounds, linksUnitPoints, type LinksHierarchy, type MapUnitType, type UnitPointProperties } from "./map-data";

/**
 * A unit's Map page (z2qt08, owner 2026-11-23): every legal unit and establishment of its
 * enterprise, the page's own unit ringed. A unit with coordinates is a solid dot at them; a
 * unit with only a region is a hollow dot at the region's centre, as it is somewhere in that
 * region. Units at the same place (many shops in one municipality) are one circle with their
 * count; a click lists them. The units come from the hierarchy the unit pages already read.
 */
export function UnitsMap({ unitId, unitType }: { unitId: string; unitType: "enterprise" | "legal_unit" | "establishment" }) {
  const { hierarchy } = useStatisticalUnitHierarchy(unitId, unitType);
  const [unitTypes, setUnitTypes] = useState<MapUnitType[]>(["legal_unit", "establishment"]);
  const [picked, setPicked] = useState<UnitPointProperties[] | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const shownRef = useRef<GeoJSON.Feature<GeoJSON.Point, UnitPointProperties>[]>([]);

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

  const fit = useCallback(() => {
    const map = mapRef.current;
    const bounds = featureBounds(shownRef.current);
    if (!map || !bounds) return;
    const [w, s, e, n] = bounds;
    if (e - w < 0.001 && n - s < 0.001) map.easeTo({ center: [w, s], zoom: 11 });
    else map.fitBounds(bounds, { padding: 60, maxZoom: 14 });
  }, []);

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      // Units at exactly the same place are clustered into one circle (a tiny radius, so only
      // identical positions merge: a region's centre); the circle counts them and keeps
      // whether the page's unit is among them.
      map.addSource("units", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        cluster: true,
        clusterRadius: 1,
        clusterMaxZoom: 22,
        clusterProperties: { has_current: ["any", ["get", "current"]] },
      });
      const colour = [
        "match",
        ["get", "unit_type"],
        "legal_unit",
        cssColour("--color-legal_unit-500"),
        "establishment",
        cssColour("--color-establishment-500"),
        cssColour("--color-enterprise-500"),
      ] as unknown as string;
      map.addLayer({
        id: "unit-groups",
        type: "circle",
        source: "units",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": "#ffffff",
          "circle-stroke-color": ["case", ["get", "has_current"], "#111827", cssColour("--color-establishment-600")],
          "circle-stroke-width": ["case", ["get", "has_current"], 3, 2],
          "circle-radius": ["interpolate", ["linear"], ["sqrt", ["get", "point_count"]], 1, 9, 20, 30],
        },
      });
      map.addLayer({
        id: "unit-group-counts",
        type: "symbol",
        source: "units",
        filter: ["has", "point_count"],
        layout: { "text-field": ["get", "point_count_abbreviated"], "text-font": BASEMAP_FONT, "text-size": 11 },
        paint: { "text-color": "#1f2937" },
      });
      map.addLayer({
        id: "unit-points",
        type: "circle",
        source: "units",
        filter: ["!", ["has", "point_count"]],
        paint: {
          // Solid at the unit's own coordinates, hollow at its region's centre.
          "circle-color": ["case", ["==", ["get", "placed"], "point"], colour, "#ffffff"],
          "circle-radius": ["case", ["get", "current"], 9, 6],
          "circle-stroke-color": ["case", ["get", "current"], "#111827", ["==", ["get", "placed"], "point"], "#ffffff", colour],
          "circle-stroke-width": ["case", ["get", "current"], 3, 2],
        },
      });
      map.addLayer({
        id: "unit-labels",
        type: "symbol",
        source: "units",
        filter: ["!", ["has", "point_count"]],
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
      map.addControl(new ViewControl([{ title: "Fit all units in view", icon: "⤢", onClick: () => fit() }]), "top-left");
      for (const layer of ["unit-points", "unit-groups"]) {
        map.on("mouseenter", layer, () => (map.getCanvas().style.cursor = "pointer"));
        map.on("mouseleave", layer, () => (map.getCanvas().style.cursor = ""));
      }
      map.on("click", "unit-points", (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (f) setPicked([f.properties as UnitPointProperties]);
      });
      map.on("click", "unit-groups", async (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (!f) return;
        const source = map.getSource("units") as GeoJSONSource;
        const leaves = await source.getClusterLeaves(f.properties.cluster_id as number, 1000, 0);
        setPicked(leaves.map((l) => l.properties as UnitPointProperties).sort((a, b) => Number(b.current) - Number(a.current) || a.name.localeCompare(b.name)));
      });
      setMapReady(true);
    },
    [fit]
  );

  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("units") as GeoJSONSource | undefined)?.setData(shown);
      shownRef.current = shown.features;
      // The page lays out after the map is created, so the map measures its box again
      // before framing the units; framing at the first, smaller box zooms in too far.
      map.resize();
      fit();
      map.once("idle", () => {
        map.resize();
        fit();
      });
    },
    [shown, mapReady, fit],
    "UnitsMap:setData"
  );

  if (!points) return null;
  const unplaced = points.total - points.atPoint - points.atRegion;
  const regionName = picked && picked.length > 1 ? picked[0].region_name : undefined;
  return (
    <section className="space-y-2" data-units-map="">
      <p className="text-sm text-gray-600" data-units-map-placed="">
        {points.total.toLocaleString()} units of this enterprise: {points.atPoint.toLocaleString()} at their address,{" "}
        {points.atRegion.toLocaleString()} at their region&apos;s centre
        {unplaced > 0 ? `, ${unplaced.toLocaleString()} with no place` : ""}.
      </p>
      <div className="flex overflow-hidden rounded-md border" style={{ height: "min(70vh, 40rem)" }}>
        <div className="relative min-w-0 flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
        </div>
        <aside className="flex w-64 shrink-0 flex-col border-l text-sm">
          <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-3" data-units-map-picked="">
            {picked ? (
              <>
                {regionName && (
                  <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    {picked.length} in {regionName}
                  </p>
                )}
                <ul className="space-y-1">
                  {picked.map((u) => (
                    <li key={`${u.unit_type}:${u.id}`}>
                      <Link className="underline underline-offset-2" href={u.href}>
                        {u.name}
                      </Link>
                      {u.current && <span className="ml-1 text-xs text-gray-500">(this unit)</span>}
                      {u.placed === "region" && picked.length === 1 && (
                        <span className="block text-xs text-gray-500">Somewhere in {u.region_name}</span>
                      )}
                    </li>
                  ))}
                </ul>
              </>
            ) : (
              <p className="text-xs text-gray-500">Click a dot or a circle for its units.</p>
            )}
          </div>
          <div className="space-y-2 border-t p-3">
            <UnitTypeLegend
              selected={unitTypes}
              onChange={setUnitTypes}
              totals={totals}
              unitTypes={["legal_unit", "establishment"]}
              mixedSwatch={false}
            />
            <div className="space-y-1 text-xs text-gray-600">
              <p className="flex items-center gap-2">
                <span className="inline-block h-3 w-3 rounded-full bg-gray-500" aria-hidden /> At its address
              </p>
              <p className="flex items-center gap-2">
                <span className="inline-block h-3 w-3 rounded-full border-2 border-gray-500 bg-white" aria-hidden /> Somewhere in its region
              </p>
            </div>
          </div>
        </aside>
      </div>
    </section>
  );
}
