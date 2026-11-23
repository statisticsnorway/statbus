"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
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
  type RegionFeatureProperties,
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
  // The selection and the unit types live in the URL (?at=50&types=legal_unit,establishment), so Back,
  // a reload or a shared link land where the map was. Each step in or out is a history
  // entry; a unit-type change replaces the current one.
  const router = useRouter();
  const searchParams = useSearchParams();
  const requested = parseSelection(searchParams?.get("at") ?? null);
  const unitTypes = parseUnitTypes(searchParams?.get("types") ?? null);
  const [mapReady, setMapReady] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const featuresRef = useRef<GeoJSON.Feature<GeoJSON.Point, { total: number }>[]>([]);

  // The map's own handlers (click, fit) run outside React's render, so they read the
  // current selection and unit types from the URL at the moment they run.
  const current = useCallback(() => {
    const params = new URLSearchParams(window.location.search);
    return { at: parseSelection(params.get("at")), types: parseUnitTypes(params.get("types")) };
  }, []);
  const mapUrl = useCallback((at: MapSelection, types: readonly MapUnitType[]) => {
    const params = new URLSearchParams();
    if (at !== "") params.set("at", at === null ? "world" : at);
    if (types.join(",") !== DEFAULT_UNIT_TYPE) params.set("types", types.join(","));
    const query = params.toString();
    return query ? `/regions/map?${query}` : "/regions/map";
  }, []);
  const select = useCallback(
    (next: MapSelection) => {
      const { at, types } = current();
      if (next !== at) router.push(mapUrl(next, types), { scroll: false });
    },
    [router, mapUrl, current]
  );
  const setUnitTypes = useCallback(
    (types: MapUnitType[]) => router.replace(mapUrl(current().at, types), { scroll: false }),
    [router, mapUrl, current]
  );

  // Circle sizes follow the largest circle in view: the area grows with the count, the
  // largest in view 28 px in radius.
  const scaleToView = useCallback((map: MapLibreMap) => {
    const view = map.getBounds();
    const top = Math.max(maxTotal(featuresRef.current.filter((f) => view.contains(f.geometry.coordinates as [number, number]))), 1);
    map.setPaintProperty("region-circles", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 0, 4, Math.sqrt(top), 28]);
  }, []);

  // Frames what the selection shows. The world frames every country with units, so the
  // countries abroad are in view; the country frames its regions with at least 1% of the
  // largest one's units, so a far-off region with few units (Svalbard) does not shrink the
  // mainland; a region frames all its subregions. Bounds that are one point (a single
  // circle, or framing that kept one) centre on it at a fixed zoom per level.
  const fitSelection = useCallback(() => {
    const map = mapRef.current;
    const features = featuresRef.current;
    if (!map || features.length === 0) return;
    const { at } = current();
    const bounds = featureBounds(at === "" ? framingFeatures(features) : features);
    if (!bounds) return;
    const [west, south, east, north] = bounds;
    if (east - west < 0.01 && north - south < 0.01) {
      map.easeTo({ center: [west, south], zoom: at === null ? 2 : at === "" ? 4 : 9 });
      return;
    }
    map.fitBounds(bounds, { padding: 60, maxZoom: at === null ? 4 : 11 });
  }, [current]);

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
  // A region path the region table does not have (an old or mistyped link) shows the country.
  const selection: MapSelection =
    requested && regions && !regions.some((r) => r.path === requested) ? "" : requested;

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
  const { data: countries } = useSWR(client ? ["regions-map:countries"] : null, async () => {
    const { data, error } = await client!.from("country").select("id,name,latitude,longitude");
    if (error) throw error;
    return new Map((data ?? []).map((c) => [c.id, c]));
  });
  const countryNames = useMemo(() => (countries ? new Map([...countries].map(([id, c]) => [id, c.name])) : undefined), [countries]);

  const regionName = useMemo(() => new Map((regions ?? []).map((r) => [r.path, r.name])), [regions]);
  const nameOf = useCallback(
    (s: MapSelection) => (s === null ? "World" : s === "" ? (home?.name ?? "Country") : (regionName.get(s) ?? s)),
    [home, regionName]
  );

  // What the map draws for the selection: the children of a domestic selection, or at the
  // world every country with units at its centre (country.latitude, longitude), the
  // installation's own one among them.
  const { features, withoutCentre } = useMemo(() => {
    if (!rows || !regions) return { features: { type: "FeatureCollection" as const, features: [] }, withoutCentre: [] };
    if (selection === null) {
      const perCountry = [{ countryId: homeId ?? -1, count: world.domestic }, ...world.abroad];
      const placed: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>[] = [];
      const unplaced: { path: string; name: string; total: number }[] = [];
      for (const { countryId, count } of perCountry) {
        if (count === 0) continue;
        const c = countries?.get(countryId);
        const name = c?.name ?? String(countryId);
        // The home country is selected by "", a foreign one is shown but not entered.
        const path = countryId === homeId ? "" : `country:${countryId}`;
        if (c?.latitude == null || c.longitude == null) {
          unplaced.push({ path, name, total: count });
          continue;
        }
        placed.push({
          type: "Feature",
          geometry: { type: "Point", coordinates: [Number(c.longitude), Number(c.latitude)] },
          properties: { path, name, total: count, enterprise: 0, legal_unit: 0, establishment: 0 },
        });
      }
      return { features: { type: "FeatureCollection" as const, features: placed }, withoutCentre: unplaced };
    }
    const { features: f, withoutCentre: w } = regionFeatures(regions, childCounts(rows, selection, homeId), unitTypes);
    return { features: f, withoutCentre: w };
  }, [rows, regions, selection, homeId, unitTypes, world, countries]);

  const selectedCounts = useMemo(
    () => (rows && selection !== null ? countsUnder(rows, selection, homeId) : null),
    [rows, selection, homeId]
  );

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
      map.on("mouseenter", "region-circles", (e: MapLayerMouseEvent) => {
        // Pointer only where a click goes in: not on foreign countries, not on the selection itself.
        const path = e.features?.[0]?.properties?.path as string | undefined;
        if (path !== undefined && !path.startsWith("country:") && path !== current().at) map.getCanvas().style.cursor = "pointer";
      });
      map.on("mouseleave", "region-circles", () => (map.getCanvas().style.cursor = ""));
      // A click on a circle selects it. A double click is a click: the map's own double-click
      // zoom is held back on circles, and the second click lands while the map is moving to
      // the new selection, so it does not select a second level.
      map.on("dblclick", "region-circles", (e: MapLayerMouseEvent) => e.preventDefault());
      map.on("click", "region-circles", (e: MapLayerMouseEvent) => {
        if (map.isMoving()) return;
        const path = e.features?.[0]?.properties?.path as string | undefined;
        // Foreign countries have no regions here: they are shown, not entered. A leaf
        // region's own circle is the selection already, so select() ignores it.
        if (path === undefined || path.startsWith("country:")) return;
        select(path);
      });
      setMapReady(true);
    },
    [scaleToView, fitSelection, select, current]
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
  // A region with no regions below it (a municipality) shows itself as its one circle.
  const isLeaf = depth > 0 && features.features.length === 1 && features.features[0].properties.path === selection;
  const childNoun = selection === null ? "countries" : depth === 0 ? "regions" : "subregions";
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
        <aside className="flex w-72 shrink-0 flex-col border-l text-sm" data-regions-map-side="">
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
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
              // The drilldown report's words and button (reports/drilldown/search-link.tsx), so the
              // two ways into the list read alike (owner 2026-11-23).
              <Button asChild size="sm" className="mt-3 w-full">
                <Link href={selectionSearch} data-regions-map-view-units="">
                  View and export statistical units
                </Link>
              </Button>
            )}
            <p className="mt-2 text-xs text-gray-500" data-regions-map-level="">
              {selection === null
                ? `The map shows ${features.features.length.toLocaleString()} ${childNoun} with units. Click ${nameOf("")} to see its regions.`
                : isLeaf
                  ? "The lowest level: no regions below this one. X or the trail above goes back up."
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
                <div data-regions-without-coordinates="">
                  <p className="flex justify-between gap-2">
                    <span>Units in regions without coordinates</span>
                    <span className="tabular-nums text-gray-600">
                      {withoutCentre.reduce((s, r) => s + r.total, 0).toLocaleString()}
                    </span>
                  </p>
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
                  <p className="mt-1 text-xs text-gray-500">
                    An admin places a region on the{" "}
                    <Link className="underline underline-offset-2" href="/regions">
                      region list
                    </Link>{" "}
                    with Place on map.
                  </p>
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
          </div>
          {/* The unit types sit at the bottom, under what is selected (owner 2026-11-23). */}
          <div className="border-t p-4">
            <UnitTypeLegend selected={unitTypes} onChange={setUnitTypes} />
          </div>
        </aside>
      </div>
    </main>
  );
}

/**
 * The unit type the map opens with: enterprises, the statistical unit, as the reports open
 * with (history-reports.tsx; owner 2026-11-23).
 */
const DEFAULT_UNIT_TYPE: MapUnitType = "enterprise";

/** ?at= in the map's URL: absent is the country, "world" the world, else a region path. */
function parseSelection(at: string | null): MapSelection {
  if (at === null || at === "") return "";
  if (at === "world") return null;
  return /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(at) ? at : "";
}

/** ?types= in the map's URL: the picked unit types, enterprises when absent or unknown. */
function parseUnitTypes(types: string | null): MapUnitType[] {
  const picked = (types ?? "").split(",").filter((t): t is MapUnitType => (MAP_UNIT_TYPES as readonly string[]).includes(t));
  return picked.length > 0 ? MAP_UNIT_TYPES.filter((t) => picked.includes(t)) : [DEFAULT_UNIT_TYPE];
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
