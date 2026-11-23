"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { X } from "lucide-react";
import { RegionsHeader } from "../regions-header";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { useTimeFrame } from "@/atoms/app-derived";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "@/components/map/unit-map";
import { UnitTypeLegend } from "@/components/map/unit-type-legend";
import { BASEMAP_FONT } from "@/components/map/basemap";
import { ViewControl } from "@/components/map/view-control";
import {
  MAP_UNIT_TYPES,
  UNIT_TYPE_SWATCH,
  childCounts,
  countsUnder,
  featureBounds,
  framingFeatures,
  maxTotal,
  regionFeatures,
  selectedTotal,
  selectionDepth,
  selectionParent,
  selectionTrail,
  worldCounts,
  type MapRegion,
  type MapSelection,
  type MapUnitType,
  type RegionCountRow,
} from "@/components/map/map-data";

/**
 * The Regions map is a drill-down (owner 2026-11-23, z2qt08). One selection decides everything:
 * the world, the installation's own country (where the page opens), or a region. The map shows
 * the selection's children, one circle each, sized by its units; clicking a circle selects it,
 * and the breadcrumb, the panel's X (one level up) and the fit button act on the selection.
 * Zooming and panning only move the view; they do not change what is shown.
 *
 * Counts come from statistical_unit_facet, the pre-aggregated counts the reports' drilldown
 * reads: one row per unit type, region path and country in the time frame (1,793 rows, 0.18 s
 * on Norway, tmp/z2qt08-map-fetch2.sql), summed here per selection.
 */
export default function RegionsMapPage() {
  const client = useAtomValue(restClientAtom);
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const [unitTypes, setUnitTypes] = useState<MapUnitType[]>(["legal_unit"]);
  const [mapReady, setMapReady] = useState(false);
  const [selection, setSelection] = useState<MapSelection>("");
  const selectionRef = useRef<MapSelection>("");
  const mapRef = useRef<MapLibreMap | null>(null);
  const featuresRef = useRef<GeoJSON.Feature<GeoJSON.Point, { total: number }>[]>([]);

  const select = useCallback((next: MapSelection) => {
    selectionRef.current = next;
    setSelection(next);
  }, []);

  // Circle sizes follow the largest circle in view: the area grows with the count, the
  // largest in view 28 px in radius.
  const scaleToView = useCallback((map: MapLibreMap) => {
    const view = map.getBounds();
    const top = Math.max(maxTotal(featuresRef.current.filter((f) => view.contains(f.geometry.coordinates as [number, number]))), 1);
    map.setPaintProperty("region-circles", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 0, 4, Math.sqrt(top), 28]);
  }, []);

  // Frames what the selection shows: its children, or a region without children by itself.
  // The world frames the country, the only place with circles until countries have centres.
  const fitSelection = useCallback(() => {
    const map = mapRef.current;
    const features = featuresRef.current;
    if (!map || features.length === 0) return;
    if (features.length === 1) {
      map.easeTo({ center: features[0].geometry.coordinates as [number, number], zoom: selectionRef.current === null ? 4 : 9 });
      return;
    }
    const bounds = featureBounds(selectionRef.current === "" ? framingFeatures(features) : features);
    if (bounds) map.fitBounds(bounds, { padding: 60, maxZoom: 11 });
  }, []);

  const { data: home } = useSWR(client ? ["regions-map:home"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(id,name)").limit(1).single();
    if (error) throw error;
    return data.country as { id: number; name: string } | null;
  });
  const homeId = home?.id ?? null;

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
      // One row per unit type, region path and country: PostgREST sums the facet's counts.
      const { data, error } = await client!
        .from("statistical_unit_facet")
        .select("unit_type,physical_region_path,physical_country_id,count.sum()")
        .lte("valid_from", validOn!)
        .gt("valid_until", validOn!);
      if (error) throw error;
      // postgrest-js cannot type an aggregate select, so the rows are typed here.
      type Row = Omit<RegionCountRow, "count"> & { sum: number };
      return ((data ?? []) as unknown as Row[]).map(({ sum, ...r }) => ({ ...r, count: sum }));
    }
  );

  const world = useMemo(() => worldCounts(rows ?? [], homeId, unitTypes), [rows, homeId, unitTypes]);
  const abroadIds = useMemo(() => world.abroad.slice(0, 10).map((a) => a.countryId), [world]);
  const { data: countryNames } = useSWR(client && abroadIds.length ? ["regions-map:countries", abroadIds.join(",")] : null, async () => {
    const { data, error } = await client!.from("country").select("id,name").in("id", abroadIds);
    if (error) throw error;
    return new Map((data ?? []).map((c) => [c.id, c.name]));
  });

  const regionName = useMemo(() => new Map((regions ?? []).map((r) => [r.path, r.name])), [regions]);
  const nameOf = useCallback(
    (s: MapSelection) => (s === null ? "World" : s === "" ? (home?.name ?? "Country") : (regionName.get(s) ?? s)),
    [home, regionName]
  );

  // What the map draws for the selection: the children of a domestic selection, or at the
  // world the country as one circle at the middle of its regions.
  const { features, withoutCentre } = useMemo(() => {
    if (!rows || !regions) return { features: { type: "FeatureCollection" as const, features: [] }, withoutCentre: [] };
    if (selection === null) {
      const counties = regionFeatures(regions, childCounts(rows, "", homeId), unitTypes).features.features;
      const bounds = featureBounds(framingFeatures(counties));
      const c = countsUnder(rows, "", homeId);
      const total = selectedTotal(c, unitTypes);
      const country: GeoJSON.Feature<GeoJSON.Point, ReturnType<typeof regionFeatures>["features"]["features"][number]["properties"]> = {
        type: "Feature",
        geometry: { type: "Point", coordinates: bounds ? [(bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2] : [0, 0] },
        properties: { path: "", name: home?.name ?? "Country", total, ...c },
      };
      return { features: { type: "FeatureCollection" as const, features: total > 0 && bounds ? [country] : [] }, withoutCentre: [] };
    }
    const { features: f, withoutCentre: w } = regionFeatures(regions, childCounts(rows, selection, homeId), unitTypes);
    return { features: f, withoutCentre: w };
  }, [rows, regions, selection, homeId, unitTypes, home]);

  const selectedCounts = useMemo(
    () => (rows && selection !== null ? countsUnder(rows, selection, homeId) : null),
    [rows, selection, homeId]
  );
  const totals = useMemo(() => {
    const t: Record<MapUnitType, number> = { enterprise: 0, legal_unit: 0, establishment: 0 };
    for (const r of rows ?? []) if (r.unit_type && (MAP_UNIT_TYPES as readonly string[]).includes(r.unit_type)) t[r.unit_type as MapUnitType] += r.count ?? 0;
    return t;
  }, [rows]);

  // The circles take the colour of the one picked unit type, grey when types are mixed.
  const circleColour = unitTypes.length === 1 ? `--color-${unitTypes[0]}-500` : "--color-informal-500";

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      map.addSource("regions", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "region-circles",
        type: "circle",
        source: "regions",
        // Smaller regions are drawn last, on top, so a small region beside a large one can be clicked.
        layout: { "circle-sort-key": ["-", 0, ["get", "total"]] },
        paint: {
          "circle-color": cssColour("--color-legal_unit-500"),
          "circle-opacity": 0.75,
          "circle-stroke-color": "#ffffff",
          "circle-stroke-width": 1.5,
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
      map.addControl(new ViewControl([{ title: "Fit the selection in view", icon: "⤢", onClick: () => fitSelection() }]), "top-left");
      map.on("moveend", () => scaleToView(map));
      map.on("mouseenter", "region-circles", () => (map.getCanvas().style.cursor = "pointer"));
      map.on("mouseleave", "region-circles", () => (map.getCanvas().style.cursor = ""));
      // A click on a circle selects it. A double click is a click: the map's own double-click
      // zoom is held back on circles, and the second click lands while the map is moving to
      // the new selection, so it does not select a second level.
      map.on("dblclick", "region-circles", (e: MapLayerMouseEvent) => e.preventDefault());
      map.on("click", "region-circles", (e: MapLayerMouseEvent) => {
        if (map.isMoving()) return;
        const path = e.features?.[0]?.properties?.path as string | undefined;
        if (path === undefined || path === selectionRef.current) return;
        select(path);
      });
      setMapReady(true);
    },
    [scaleToView, fitSelection, select]
  );

  // New data for the map; a new selection is also framed. Unit-type or time-frame changes keep
  // the view where it is.
  const framedSelection = useRef<MapSelection | undefined>(undefined);
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(features);
      featuresRef.current = features.features;
      map.setPaintProperty("region-circles", "circle-color", cssColour(circleColour));
      scaleToView(map);
      if (features.features.length > 0 && framedSelection.current !== selection) {
        framedSelection.current = selection;
        fitSelection();
      }
    },
    [features, mapReady, circleColour, selection],
    "RegionsMapPage:setData"
  );

  const depth = selectionDepth(selection);
  const childNoun = selection === null ? "country" : depth === 0 ? "regions" : "subregions";
  const shown = features.features.reduce((s, f) => s + f.properties.total, 0);
  const typesParam = `unit_type=${unitTypes.join(",")}`;
  const selectionSearch =
    selection === null ? null : selection === "" ? `/search?${typesParam}&domestic=true` : `/search?${typesParam}&physical_region_path=${encodeURIComponent(selection)}`;
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);

  return (
    <main className="flex w-full flex-col" style={{ height: "calc(100vh - 56px)" }} data-regions-map-page="">
      <div className="mx-auto w-full max-w-5xl px-2 pt-8 md:pt-12">
        <RegionsHeader
          view="map"
          breadcrumb={
            <nav aria-label="Region trail" className="flex flex-wrap items-center gap-1 text-sm" data-regions-map-trail="">
              {selectionTrail(selection).map((s, i, trail) => (
                <span key={s ?? "world"} className="flex items-center gap-1">
                  {i > 0 && <span className="text-gray-400">›</span>}
                  {i === trail.length - 1 ? (
                    <span className="font-medium" aria-current="location">
                      {nameOf(s)}
                    </span>
                  ) : (
                    <button type="button" className="underline-offset-2 hover:underline" onClick={() => select(s)}>
                      {nameOf(s)}
                    </button>
                  )}
                </span>
              ))}
            </nav>
          }
        />
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
          <section className="relative rounded border-2 border-gray-900 bg-gray-50 p-3" data-regions-map-selection="">
            {selection !== null && (
              <button
                type="button"
                className="absolute right-1.5 top-1.5 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                title={`Back to ${nameOf(selectionParent(selection))}`}
                aria-label={`Back to ${nameOf(selectionParent(selection))}`}
                onClick={() => select(selectionParent(selection))}
              >
                <X className="h-4 w-4" />
              </button>
            )}
            <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
              {selection === null ? "Everywhere" : depth === 0 ? "Selected country" : "Selected region"}
            </p>
            <h2 className="font-medium">
              {nameOf(selection)}
              {depth > 0 && <span className="ml-1.5 text-xs font-normal text-gray-500">{selection}</span>}
            </h2>
            {selectedCounts ? (
              <dl className="mt-2 grid grid-cols-[1fr_auto] gap-x-3 gap-y-0.5">
                {MAP_UNIT_TYPES.map((t) => (
                  <PickedCount key={t} unitType={t} value={selectedCounts[t]} />
                ))}
              </dl>
            ) : (
              <WorldSplit world={world} homeName={nameOf("")} countryNames={countryNames} typesParam={typesParam} />
            )}
            {selectionSearch && (
              <Link className="mt-2 inline-block underline underline-offset-2" href={selectionSearch}>
                Search these units
              </Link>
            )}
            <p className="mt-2 text-xs text-gray-500" data-regions-map-level="">
              {selection === null
                ? "Click the country to see its regions."
                : features.features.length > 0
                  ? `The map shows ${shown.toLocaleString()} units in ${features.features.length.toLocaleString()} ${childNoun}. Click a circle to go into it, X or the trail above to go back up.`
                  : "No units of the picked types here."}
            </p>
          </section>
          {selection !== null && ((depth === 0 && world.domesticWithoutRegion > 0) || withoutCentre.length > 0) && (
            <section className="space-y-2" data-regions-not-on-map="">
              <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">Not on the map</h2>
              {depth === 0 && world.domesticWithoutRegion > 0 && (
                <CountLink
                  href={`/search?${typesParam}&domestic=true&physical_region_path=null`}
                  label={`Units in ${nameOf("")} without a region`}
                  value={world.domesticWithoutRegion}
                  data="units-without-region"
                />
              )}
              {withoutCentre.length > 0 && (
                <div>
                  <CountLink
                    href="/regions?coordinates=none"
                    label="Units in regions without coordinates"
                    value={withoutCentre.reduce((s, r) => s + r.total, 0)}
                    data="regions-without-coordinates"
                  />
                  <ul className="mt-0.5 space-y-0.5 pl-3 text-xs text-gray-600">
                    {withoutCentre.map((r) => (
                      <li key={r.path} className="flex justify-between gap-2">
                        <span className="truncate" title={`${r.path} ${r.name}`}>
                          {r.path} {r.name}
                        </span>
                        <span className="tabular-nums">{r.total.toLocaleString()}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </section>
          )}
          {depth === 0 && (
            <p className="text-xs text-gray-500">
              Outside {nameOf("")}: {abroadTotal.toLocaleString()} units abroad and {world.noLocation.toLocaleString()} without a
              location.{" "}
              <button type="button" className="underline underline-offset-2" onClick={() => select(null)}>
                Show everywhere
              </button>
            </p>
          )}
        </aside>
      </div>
    </main>
  );
}

/** The world selection's panel: the units in the country, abroad by country, and without a location. */
function WorldSplit({
  world,
  homeName,
  countryNames,
  typesParam,
}: {
  world: ReturnType<typeof worldCounts>;
  homeName: string;
  countryNames: Map<number, string> | undefined;
  typesParam: string;
}) {
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);
  const shownAbroad = world.abroad.slice(0, 10);
  const rest = abroadTotal - shownAbroad.reduce((s, a) => s + a.count, 0);
  return (
    <div className="mt-2 space-y-1.5" data-regions-map-world="">
      <CountLink href={`/search?${typesParam}&domestic=true`} label={`In ${homeName}`} value={world.domestic} data="domestic" />
      <div>
        <CountLink
          href={`/search?${typesParam}&domestic=false`}
          label={`Abroad, in ${world.abroad.length.toLocaleString()} countries`}
          value={abroadTotal}
          data="abroad"
        />
        <ul className="mt-0.5 space-y-0.5 pl-3 text-xs text-gray-600">
          {shownAbroad.map((a) => (
            <li key={a.countryId} className="flex justify-between gap-2">
              <span className="truncate">{countryNames?.get(a.countryId) ?? "…"}</span>
              <span className="tabular-nums">{a.count.toLocaleString()}</span>
            </li>
          ))}
          {rest > 0 && (
            <li className="flex justify-between gap-2">
              <span>Other countries</span>
              <span className="tabular-nums">{rest.toLocaleString()}</span>
            </li>
          )}
        </ul>
      </div>
      <CountLink href={`/search?${typesParam}&physical_location=missing`} label="No location" value={world.noLocation} data="no-location" />
    </div>
  );
}

function CountLink({ href, label, value, data }: { href: string; label: string; value: number; data: string }) {
  return (
    <Link className="flex justify-between gap-2 underline-offset-2 hover:underline" href={href} data-count-link={data}>
      <span>{label}</span>
      <span className="tabular-nums text-gray-600">{value.toLocaleString()}</span>
    </Link>
  );
}

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
