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
import { RegionSpiders } from "./region-spiders";
import { ChildList, type ChildRow } from "./child-list";
import {
  MAP_UNIT_TYPES,
  UNIT_TYPE_SWATCH,
  childCounts,
  countryCounts,
  countsUnder,
  featureBounds,
  framingFeatures,
  maxTotal,
  regionFeatures,
  selectedCountryCode,
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
 * the world, the installation's own country (where the page opens), a foreign country, or a
 * region. The map shows the selection's children, one circle each, sized by its units, and the
 * panel lists the same children (owner 2026-11-24, as on a unit's Map page). A click on a circle
 * or a row picks that child: its row opens with its units per type and View and download, and its
 * circle is ringed. A double click on a circle, or the row's arrow, goes in; the breadcrumb, the
 * panel's X (one level up) and the fit button act on the selection.
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
  // The map once its style has loaded: the type legs render over it.
  const [readyMap, setReadyMap] = useState<MapLibreMap | null>(null);
  const mapReady = readyMap !== null;
  const mapRef = useRef<MapLibreMap | null>(null);
  const featuresRef = useRef<GeoJSON.Feature<GeoJSON.Point, { total: number }>[]>([]);
  // The child picked by a click on its circle or row, with the selection it was picked in: a new
  // selection (going in, Back, the trail) leaves it behind, so it shows only where it was picked.
  const [pickedChild, setPickedChild] = useState<{ at: MapSelection; path: string } | null>(null);

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
    // The picked circle's ring sits just outside it, at the same scale.
    map.setPaintProperty("picked-region-ring", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 0, 8, Math.sqrt(top), 32]);
  }, []);

  // Picks one child of the selection, from a click on its circle, one of its type legs or its row
  // (null: none). Its circle is ringed on the map; a row picked in the list also brings its
  // circle into view.
  const pickChild = useCallback(
    (path: string | null, from: "map" | "list" = "map") => {
      setPickedChild(path === null ? null : { at: current().at, path });
      const map = mapRef.current;
      const f = featuresRef.current.find((x) => (x.properties as unknown as RegionFeatureProperties).path === path);
      (map?.getSource("picked-region") as GeoJSONSource | undefined)?.setData({ type: "FeatureCollection", features: f ? [f] : [] });
      if (map && f && from === "list" && !map.getBounds().contains(f.geometry.coordinates as [number, number])) {
        map.easeTo({ center: f.geometry.coordinates as [number, number] });
      }
    },
    [current, setPickedChild]
  );

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
      // A foreign country is its one circle, at its centre.
      map.easeTo({ center: [west, south], zoom: at === null ? 2 : selectionDepth(at) === 0 ? 4 : 9 });
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
  const { data: countries } = useSWR(client ? ["regions-map:countries"] : null, async () => {
    const { data, error } = await client!.from("country").select("id,iso_2,name,latitude,longitude");
    if (error) throw error;
    return new Map((data ?? []).map((c) => [c.id, c]));
  });
  const countryByCode = useMemo(() => new Map([...(countries?.values() ?? [])].map((c) => [c.iso_2, c])), [countries]);
  // A region path or country code the tables do not have (an old or mistyped link) shows the
  // installation's own country, as does its own code.
  const requestedCode = selectedCountryCode(requested);
  const selection: MapSelection =
    requestedCode !== null
      ? countries && (!countryByCode.has(requestedCode) || countryByCode.get(requestedCode)?.id === home?.id)
        ? ""
        : requested
      : requested && regions && !regions.some((r) => r.path === requested)
        ? ""
        : requested;
  const selectedCountry = countryByCode.get(selectedCountryCode(selection) ?? "") ?? null;

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
  const perCountry = useMemo(() => countryCounts(rows ?? []), [rows]);

  const regionName = useMemo(() => new Map((regions ?? []).map((r) => [r.path, r.name])), [regions]);
  const nameOf = useCallback(
    (s: MapSelection) => {
      if (s === null) return "World";
      if (s === "") return home?.name ?? "Country";
      const code = selectedCountryCode(s);
      return code !== null ? (countryByCode.get(code)?.name ?? code) : (regionName.get(s) ?? s);
    },
    [home, regionName, countryByCode]
  );

  // What the map draws for the selection: the children of a domestic selection; at the world
  // every country with units at its centre (country.latitude, longitude), the installation's
  // own one among them; a foreign country, which has no regions here, as its one circle.
  const { features, withoutCentre } = useMemo(() => {
    if (!rows || !regions) return { features: { type: "FeatureCollection" as const, features: [] }, withoutCentre: [] };
    if (selection === null || selectedCountry) {
      const placed: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>[] = [];
      const unplaced: { path: string; name: string; total: number }[] = [];
      for (const [countryId, counts] of perCountry) {
        if (selectedCountry && countryId !== selectedCountry.id) continue;
        const total = selectedTotal(counts, unitTypes);
        if (total === 0) continue;
        const c = countries?.get(countryId);
        const name = c?.name ?? String(countryId);
        // The installation's own country is selected by "", a foreign one by its code.
        const path = countryId === homeId ? "" : `country:${c?.iso_2 ?? countryId}`;
        if (c?.latitude == null || c.longitude == null) {
          unplaced.push({ path, name, total });
          continue;
        }
        placed.push({
          type: "Feature",
          geometry: { type: "Point", coordinates: [Number(c.longitude), Number(c.latitude)] },
          properties: { path, name, total, ...counts },
        });
      }
      return { features: { type: "FeatureCollection" as const, features: placed }, withoutCentre: unplaced };
    }
    const { features: f, withoutCentre: w } = regionFeatures(regions, childCounts(rows, selection, homeId), unitTypes);
    return { features: f, withoutCentre: w };
  }, [rows, regions, selection, selectedCountry, homeId, unitTypes, perCountry, countries]);

  const selectedCounts = useMemo(() => {
    if (!rows || selection === null) return null;
    if (selectedCountry) return perCountry.get(selectedCountry.id) ?? { enterprise: 0, legal_unit: 0, establishment: 0 };
    return countsUnder(rows, selection, homeId);
  }, [rows, selection, selectedCountry, perCountry, homeId]);

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
          "circle-radius": 6,
        },
      });
      // The picked child's circle: a dark ring round it (owner 2026-11-24, as on a unit's Map page).
      map.addSource("picked-region", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "picked-region-ring",
        type: "circle",
        source: "picked-region",
        paint: {
          "circle-color": "rgba(0,0,0,0)",
          "circle-radius": ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 0, 8, 1000, 32],
          "circle-stroke-color": "#111827",
          "circle-stroke-width": 3,
        },
      });
      map.addLayer({
        id: "region-labels",
        type: "symbol",
        source: "regions",
        layout: {
          "text-field": ["concat", ["get", "name"], "\n", ["number-format", ["get", "total"], { locale: "en" }]],
          "text-font": BASEMAP_FONT,
          "text-size": 13,
          "text-allow-overlap": false,
        },
        paint: { "text-color": "#1f2937", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
      });
      map.addControl(new ViewControl([{ title: "Fit the selection in view", icon: "⤢", onClick: () => fitSelection() }]), "top-left");
      map.on("moveend", () => scaleToView(map));
      map.on("mouseenter", "region-circles", () => (map.getCanvas().style.cursor = "pointer"));
      map.on("mouseleave", "region-circles", () => (map.getCanvas().style.cursor = ""));
      // A click on a circle previews it, a double click goes in (owner 2026-11-23: the labels
      // are too small to read, so a click first shows the circle readably). The map's own
      // double-click zoom is held back on circles; going in frames the new selection instead.
      // A leaf region's own circle is the selection already, so select() ignores it.
      map.on("dblclick", "region-circles", (e: MapLayerMouseEvent) => {
        e.preventDefault();
        const path = e.features?.[0]?.properties?.path as string | undefined;
        if (path !== undefined) select(path);
      });
      map.on("click", (e) => {
        const feature = map.queryRenderedFeatures(e.point, { layers: ["region-circles"] })[0] as unknown as
          | GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>
          | undefined;
        if (!feature) return pickChild(null);
        pickChild(feature.properties.path);
      });
      setReadyMap(map);
    },
    [scaleToView, fitSelection, select, setReadyMap, pickChild]
  );

  // New data for the map; a new selection is also framed. Unit-type or time-frame changes keep
  // the view where it is.
  // The framed selection, and the picked child (only where it was picked: a new selection leaves it behind).
  const framedSelection = useRef<MapSelection | undefined>(undefined);
  const picked = pickedChild && pickedChild.at === selection ? pickedChild.path : null;
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(features);
      featuresRef.current = features.features;
      map.setPaintProperty("region-circles", "circle-color", cssColour(circleColour));
      scaleToView(map);
      // The ring follows the picked child's circle; at another selection there is none.
      const ringed = picked ? features.features.filter((f) => f.properties.path === picked) : [];
      (map.getSource("picked-region") as GeoJSONSource | undefined)?.setData({ type: "FeatureCollection", features: ringed });
      if (features.features.length > 0 && framedSelection.current !== selection) {
        framedSelection.current = selection;
        fitSelection();
      }
    },
    [features, mapReady, circleColour, selection, picked],
    "RegionsMapPage:setData"
  );

  const depth = selectionDepth(selection);
  // A region with no regions below it (a municipality) shows itself as its one circle.
  const isLeaf = depth > 0 && features.features.length === 1 && features.features[0].properties.path === selection;
  const childNoun = selection === null ? "countries" : depth === 0 ? "regions" : "subregions";
  const typesParam = `unit_type=${unitTypes.join(",")}`;
  // The search list for a selection: the country's own units, a foreign country's units, or a region's.
  const searchFor = (s: MapSelection) => {
    if (s === null) return `/search?${typesParam}`;
    if (s === "") return `/search?${typesParam}&domestic=true`;
    const code = selectedCountryCode(s);
    if (code !== null) return `/search?${typesParam}&physical_country=${countryByCode.get(code)?.id ?? ""}`;
    return `/search?${typesParam}&physical_region_path=${encodeURIComponent(s)}`;
  };
  const selectionSearch = searchFor(selection);
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);
  // The panel's list: the children the map draws. A region with regions below it can be entered;
  // a foreign country has none here, but going in shows it alone with its counts.
  const parentPaths = useMemo(() => new Set((regions ?? []).map((r) => r.path.split(".").slice(0, -1).join("."))), [regions]);
  const childRows: ChildRow[] = isLeaf
    ? []
    : features.features.map((f) => {
        const p = f.properties;
        const country = p.path === "" || p.path.startsWith("country:");
        return {
          path: p.path,
          name: p.name,
          code: country ? null : p.path,
          counts: { enterprise: p.enterprise, legal_unit: p.legal_unit, establishment: p.establishment },
          canEnter: country || parentPaths.has(p.path),
        };
      });

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
          {readyMap && (
            <RegionSpiders
              map={readyMap}
              features={features.features}
              unitTypes={unitTypes}
              focus={picked}
              onPick={(f) => pickChild(f.properties.path)}
            />
          )}
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
              // One list of unit types: tick to show a type on the map and in the list the button
              // opens; the count is the selection's (owner 2026-11-23: the types were listed twice,
              // as counts here and as a legend at the bottom).
              <div className="mt-3">
                <UnitTypeLegend selected={unitTypes} onChange={setUnitTypes} totals={selectedCounts} />
              </div>
            ) : (
              <WorldSplit world={world} homeName={nameOf("")} typesParam={typesParam} />
            )}
            {selection === null && (
              <div className="mt-3 border-t pt-3">
                <UnitTypeLegend selected={unitTypes} onChange={setUnitTypes} />
              </div>
            )}
            {selectionSearch && (
              // The drilldown report's button (reports/drilldown/search-link.tsx), under the types it
              // opens, so the two ways into the list read alike (owner 2026-11-23).
              <Button asChild size="sm" className="mt-3 w-full">
                <Link href={selectionSearch} data-regions-map-view-units="">
                  View and download
                </Link>
              </Button>
            )}
            <p className="mt-2 text-xs text-gray-500" data-regions-map-level="">
              {selectedCountry
                ? `This registry has no regions of ${selectedCountry.name}. X or the trail above goes back up.`
                : isLeaf
                  ? "The lowest level: no regions below this one. X or the trail above goes back up."
                  : features.features.length === 0
                    ? "No units of the picked types here."
                    : null}
            </p>
          </section>
          {childRows.length > 0 && (
            <ChildList
              heading={`${features.features.length.toLocaleString()} ${childNoun}`}
              rows={childRows}
              unitTypes={unitTypes}
              picked={picked}
              searchFor={searchFor}
              onPick={(path) => pickChild(path, "list")}
              onEnter={select}
            />
          )}
          {selection !== null && !selectedCountry && ((selection === "" && world.domesticWithoutRegion > 0) || withoutCentre.length > 0) && (
            <section className="space-y-2" data-regions-not-on-map="">
              <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">Not on the map</h2>
              {selection === "" && world.domesticWithoutRegion > 0 && (
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
          {selection === "" && (
            <p className="text-xs text-gray-500">
              Outside {nameOf("")}: {abroadTotal.toLocaleString()} units abroad and {world.noLocation.toLocaleString()} without a
              location.{" "}
              <button type="button" className="underline underline-offset-2" onClick={() => select(null)}>
                Show everywhere
              </button>
            </p>
          )}
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

/** ?at= in the map's URL: absent is the country, "world" the world, "country:SE" a foreign country, else a region path. */
function parseSelection(at: string | null): MapSelection {
  if (at === null || at === "") return "";
  if (at === "world") return null;
  if (/^country:[A-Z]{2}$/.test(at)) return at;
  return /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(at) ? at : "";
}

/** ?types= in the map's URL: the picked unit types, enterprises when absent or unknown. */
function parseUnitTypes(types: string | null): MapUnitType[] {
  const picked = (types ?? "").split(",").filter((t): t is MapUnitType => (MAP_UNIT_TYPES as readonly string[]).includes(t));
  return picked.length > 0 ? MAP_UNIT_TYPES.filter((t) => picked.includes(t)) : [DEFAULT_UNIT_TYPE];
}

/**
 * The world selection's summary: the units in the installation's own country, abroad, and without
 * a location. The countries themselves, each pickable and enterable, are the list below it
 * (ChildList), as the regions are at the other levels.
 */
function WorldSplit({
  world,
  homeName,
  typesParam,
}: {
  world: ReturnType<typeof worldCounts>;
  homeName: string;
  typesParam: string;
}) {
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);
  return (
    <div className="mt-2 space-y-1" data-regions-map-world="">
      <p className="flex justify-between gap-2" data-count="domestic">
        <span>In {homeName}</span>
        <span className="tabular-nums text-gray-600">{world.domestic.toLocaleString()}</span>
      </p>
      <p className="flex justify-between gap-2" data-count="abroad">
        <span>Abroad, in {world.abroad.length.toLocaleString()} countries</span>
        <span className="tabular-nums text-gray-600">{abroadTotal.toLocaleString()}</span>
      </p>
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
