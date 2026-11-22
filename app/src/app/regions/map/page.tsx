"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { useTimeFrame } from "@/atoms/app-derived";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "@/components/map/unit-map";
import { UnitTypeLegend } from "@/components/map/unit-type-legend";
import { BASEMAP_FONT } from "@/components/map/basemap";
import {
  MAP_UNIT_TYPES,
  UNIT_TYPE_SWATCH,
  countsByRegion,
  depthForZoom,
  featureBounds,
  framingFeatures,
  maxRegionDepth,
  maxTotal,
  regionFeatures,
  selectedTotal,
  unplacedCount,
  type MapRegion,
  type MapUnitType,
  type RegionCountRow,
} from "@/components/map/map-data";

/**
 * Each region at its centre with its number of units, top-level regions first and one level
 * deeper per zoom band, as deep as the region tree goes (Norway 2, Morocco 5) (z2qt08, owner
 * 2026-11-22). Counts come from statistical_unit_facet, the pre-aggregated counts the reports'
 * drilldown reads, grouped by region path prefix: 0.15 s on Norway against 2.8 s counting
 * statistical_unit (tmp/hug/z2qt08-data/q9.log), 0.10 s on Morocco. Regions without a centre
 * are listed beside the map.
 */
export default function RegionsMapPage() {
  const client = useAtomValue(restClientAtom);
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const [unitTypes, setUnitTypes] = useState<MapUnitType[]>(["legal_unit"]);
  const [zoom, setZoom] = useState(4);
  const [mapReady, setMapReady] = useState(false);
  const [picked, setPicked] = useState<PickedRegion | null>(null);
  const fitted = useRef(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const featuresRef = useRef<GeoJSON.Feature<GeoJSON.Point, { total: number }>[]>([]);
  // Circle sizes follow the largest region in view, so municipalities are as readable as
  // counties: the area grows with the count, the largest in view 28 px across in radius.
  const scaleToView = useCallback((map: MapLibreMap) => {
    const view = map.getBounds();
    const top = Math.max(maxTotal(featuresRef.current.filter((f) => view.contains(f.geometry.coordinates as [number, number]))), 1);
    map.setPaintProperty("region-circles", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 0, 4, Math.sqrt(top), 28]);
  }, []);

  const { data: regions } = useSWR(client ? ["regions-map:regions"] : null, async () => {
    const { data, error } = await client!
      .from("region")
      .select("path,name,center_latitude,center_longitude")
      .order("path");
    if (error) throw error;
    return (data ?? []) as MapRegion[];
  });

  const { data: rows, error: countError } = useSWR(
    client && validOn ? ["regions-map:counts", validOn] : null,
    async () => {
      // One row per unit type and region path: PostgREST sums the facet's counts for the frame.
      const { data, error } = await client!
        .from("statistical_unit_facet")
        .select("unit_type,physical_region_path,count.sum()")
        .lte("valid_from", validOn!)
        .gt("valid_until", validOn!);
      if (error) throw error;
      // postgrest-js cannot type an aggregate select, so the rows are typed here.
      return ((data ?? []) as unknown as { unit_type: RegionCountRow["unit_type"]; physical_region_path: string | null; sum: number }[]).map(
        (r) => ({ unit_type: r.unit_type, physical_region_path: r.physical_region_path, count: r.sum })
      );
    }
  );

  const maxDepth = useMemo(() => maxRegionDepth(regions ?? []), [regions]);
  const depth = depthForZoom(zoom, maxDepth);
  const counts = useMemo(() => (rows ? countsByRegion(rows, depth) : []), [rows, depth]);
  const totals = useMemo(() => {
    const t: Record<MapUnitType, number> = { enterprise: 0, legal_unit: 0, establishment: 0 };
    for (const c of rows ? countsByRegion(rows, 1) : []) for (const u of MAP_UNIT_TYPES) t[u] += c.counts[u];
    return t;
  }, [rows]);
  const { features, withoutCentre } = useMemo(
    () => regionFeatures(regions ?? [], counts, unitTypes),
    [regions, counts, unitTypes]
  );
  const unplaced = rows ? unplacedCount(rows, unitTypes) : 0;
  const shown = features.features.reduce((s, f) => s + f.properties.total, 0);

  // The circles take the colour of the one picked unit type, grey when types are mixed.
  const circleColour = unitTypes.length === 1 ? `--color-${unitTypes[0]}-500` : "--color-informal-500";

  const onReady = useCallback((map: MapLibreMap) => {
    mapRef.current = map;
    map.addSource("regions", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addLayer({
      id: "region-circles",
      type: "circle",
      source: "regions",
      layout: {
        // Smaller regions are drawn last, on top, so a small region beside a large one can be clicked.
        "circle-sort-key": ["-", 0, ["get", "total"]],
      },
      paint: {
        "circle-color": cssColour("--color-legal_unit-500"),
        "circle-opacity": 0.75,
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 1.5,
        // Area grows with the count: radius by its square root, up to 28 px for the largest
        // region shown (set with the data).
        "circle-radius": 4,
      },
    });
    map.addLayer({
      id: "region-labels",
      type: "symbol",
      source: "regions",
      layout: {
        "text-field": ["concat", ["get", "name"], "\n", ["number-format", ["get", "total"], { locale: "en" }]],
        "text-font": BASEMAP_FONT,
        "text-size": 11,
        "text-allow-overlap": false,
      },
      paint: { "text-color": "#1f2937", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
    });
    map.on("zoomend", () => setZoom(map.getZoom()));
    map.on("moveend", () => scaleToView(map));
    map.on("mouseenter", "region-circles", () => (map.getCanvas().style.cursor = "pointer"));
    map.on("mouseleave", "region-circles", () => (map.getCanvas().style.cursor = ""));
    map.on("click", "region-circles", (e: MapLayerMouseEvent) => {
      const f = e.features?.[0];
      if (!f) return;
      setPicked(f.properties as PickedRegion);
    });
    setMapReady(true);
  }, [scaleToView]);

  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(features);
      featuresRef.current = features.features;
      map.setPaintProperty("region-circles", "circle-color", cssColour(circleColour));
      scaleToView(map);
      const bounds = featureBounds(framingFeatures(features.features));
      if (!fitted.current && bounds && depth === 1) {
        map.fitBounds(bounds, { padding: 60, duration: 0 });
        fitted.current = true;
      }
    },
    [features, mapReady, circleColour, depth],
    "RegionsMapPage:setData"
  );

  return (
    <main className="flex w-full flex-col" style={{ height: "calc(100vh - 56px)" }} data-regions-map-page="">
      <div className="flex items-center justify-between gap-4 border-b px-4 py-2">
        <div className="flex items-baseline gap-3">
          <h1 className="text-lg font-medium">Regions map</h1>
          <span className="text-sm text-gray-600">
            Level {depth} of {Math.max(maxDepth, 1)}: {shown.toLocaleString()} units
            {validOn && <> on {validOn}</>}
          </span>
        </div>
        <Link href="/regions" className="text-sm underline underline-offset-2">
          Region list
        </Link>
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="relative min-w-0 flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
          {countError && (
            <p className="absolute left-1/2 top-4 -translate-x-1/2 rounded bg-red-50 px-3 py-2 text-sm text-red-700 shadow" role="alert">
              {countError instanceof Error ? countError.message : String(countError)}
            </p>
          )}
        </div>
        <aside className="w-72 shrink-0 space-y-4 overflow-y-auto border-l p-4 text-sm" data-regions-map-side="">
          <UnitTypeLegend selected={unitTypes} onChange={setUnitTypes} totals={totals} />
          {picked && (
            <section className="rounded border bg-gray-50 p-3" data-picked-region="">
              <h2 className="font-medium">{picked.name}</h2>
              <p className="text-xs text-gray-500">{picked.path}</p>
              <dl className="mt-2 grid grid-cols-[1fr_auto] gap-x-3 gap-y-0.5">
                {MAP_UNIT_TYPES.map((t) => (
                  <PickedCount key={t} unitType={t} value={Number(picked[t])} />
                ))}
              </dl>
              <Link
                className="mt-2 inline-block underline underline-offset-2"
                href={`/search?physical_region_path=${encodeURIComponent(picked.path)}&unit_type=${unitTypes.join(",")}`}
              >
                Search these units
              </Link>
            </section>
          )}
          {(withoutCentre.length > 0 || unplaced > 0) && (
            <section data-regions-without-centre="">
              <h2 className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-500">Not on the map</h2>
              <ul className="space-y-0.5">
                {withoutCentre.map((r) => (
                  <li key={r.path} className="flex justify-between gap-2">
                    <span className="truncate" title={`${r.path} ${r.name}`}>
                      {r.path} {r.name}
                    </span>
                    <span className="tabular-nums text-gray-600">{r.total.toLocaleString()}</span>
                  </li>
                ))}
                {unplaced > 0 && (
                  <li className="flex justify-between gap-2">
                    <span>No region</span>
                    <span className="tabular-nums text-gray-600">{unplaced.toLocaleString()}</span>
                  </li>
                )}
              </ul>
              <p className="mt-1 text-xs text-gray-500">Regions without a centre (latitude and longitude) in the region list.</p>
            </section>
          )}
          <p className="text-xs text-gray-500">
            Of the picked units, {selectedTotal(totals, unitTypes).toLocaleString()} have a region.
          </p>
        </aside>
      </div>
    </main>
  );
}

type PickedRegion = { path: string; name: string; total: number } & Record<MapUnitType, number>;

const UNIT_TYPE_PLURAL: Record<MapUnitType, string> = {
  enterprise: "Enterprises",
  legal_unit: "Legal units",
  establishment: "Establishments",
};

function PickedCount({ unitType, value }: { unitType: MapUnitType; value: number }) {
  return (
    <>
      <dt className="flex items-center gap-1.5">
        <span className={`inline-block h-2.5 w-2.5 rounded-full ${UNIT_TYPE_SWATCH[unitType]}`} aria-hidden />
        {UNIT_TYPE_PLURAL[unitType]}
      </dt>
      <dd className="text-right tabular-nums">{value.toLocaleString()}</dd>
    </>
  );
}
