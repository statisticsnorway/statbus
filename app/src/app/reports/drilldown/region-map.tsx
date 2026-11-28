"use client";

// The Drilldown's region panel, flipped to a map (ppvxg2, owner 2026-11-28 14:02): the same
// regions, measures and drill as the bars, drawn as circles at each region's coordinates beside a
// table of the figures. It reads nothing of its own for the figures: they are the Drilldown's
// answer (statistical_unit_facet_drilldown), so bars and map always agree. Only the region
// coordinates and, at the lowest level, the region's first units are read here.
import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { Eye, SquareArrowOutUpRight, X } from "lucide-react";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "@/components/map/unit-map";
import { BASEMAP_FONT, BASEMAP_FONT_BOLD } from "@/components/map/basemap";
import { featureBounds, UNIT_PATH, type MapUnitType } from "@/components/map/map-data";
import { ViewControl } from "@/components/map/view-control";
import { MapEmptyNote, MapPanelSkeleton } from "@/components/map/map-panel-states";
import { ACTIVITY_CATEGORY_PATH, REGION, UNIT_TYPE } from "@/app/search/filters/url-search-params";
import type { DrillDownPoint } from "@/app/reports/types/drill-down";
import { reportingOf, valueOf, type Figures, type Measure } from "./measures";
import { readRegionUnits } from "./region-units";

interface MapRegion {
  path: string;
  code: string | null;
  name: string;
  latitude: number | null;
  longitude: number | null;
}

const parentOf = (p: string) => p.split(".").slice(0, -1).join(".");
const whole = (x: number) => Math.round(x).toLocaleString("en");
const oneDecimal = (x: number) => x.toLocaleString("en", { maximumFractionDigits: 1 });

export function RegionMap({
  points,
  selection,
  trail,
  region,
  onSelect,
  ringed,
  onRing: setRinged,
  measures,
  unitType,
  unitsLabel,
  activityCategory,
  validOn,
  frameName,
  isLoading,
}: {
  /** The selection's parts with their figures, the bars' own points. */
  readonly points: DrillDownPoint[] | null | undefined;
  /** The selection's own figures, as the Drilldown's answer gives them. */
  readonly selection: Figures | null | undefined;
  /** The regions from the top down to the selection, the bars' breadcrumb. */
  readonly trail: DrillDownPoint[] | null | undefined;
  readonly region: DrillDownPoint | null;
  readonly onSelect: (p: DrillDownPoint | null) => void;
  /** The region the eye marks: ringed on the map, its bar picked out in the bars (owner
   * 2026-11-28 14:46), so the mark survives a flip between the views. */
  readonly ringed: string | null;
  readonly onRing: (path: string | null) => void;
  /** The measures shown as columns, the primary first: it sizes the circles and orders the rows. */
  readonly measures: readonly Measure[];
  readonly unitType: UnitType;
  readonly unitsLabel: string;
  readonly activityCategory: DrillDownPoint | null;
  readonly validOn: string | null;
  readonly frameName: string | null;
  readonly isLoading: boolean;
}) {
  const client = useAtomValue(restClientAtom);
  const at = region?.path ?? "";
  const primary = measures[0];
  const mapRef = useRef<MapLibreMap | null>(null);
  const [mapReady, setMapReady] = useState(false);

  const { data: countryName } = useSWR(client ? ["drilldown-map:country"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(name)").limit(1).single();
    if (error) throw error;
    return (data.country as { name: string } | null)?.name ?? null;
  });
  const { data: regions } = useSWR(client ? ["drilldown-map:regions"] : null, async () => {
    const { data, error } = await client!.from("region").select("path,code,name,latitude,longitude").order("path");
    if (error) throw error;
    return (data ?? []) as MapRegion[];
  });
  const byPath = useMemo(() => new Map((regions ?? []).map((r) => [r.path, r])), [regions]);
  const hasChildren = useMemo(() => new Set((regions ?? []).map((r) => parentOf(r.path))), [regions]);
  const isLeaf = at !== "" && regions !== undefined && !hasChildren.has(at);
  const nameOf = useCallback(
    (p: string) => (p ? (byPath.get(p)?.name ?? p) : (countryName ?? "Country")),
    [byPath, countryName]
  );

  // The parts of this selection only: while the next level is read the answer before it is kept.
  const parts = useMemo(
    () =>
      isLeaf
        ? []
        : [...(points ?? [])]
            .filter((p) => parentOf(p.path) === at)
            .sort((a, b) => valueOf(b, primary.key) - valueOf(a, primary.key)),
    [points, isLeaf, at, primary]
  );
  const go = useCallback(
    (p: DrillDownPoint | null) => {
      setRinged(null);
      onSelect(p);
    },
    [onSelect, setRinged]
  );
  const goPath = useCallback(
    (path: string) => {
      if (!path) return go(null);
      const known = parts.find((p) => p.path === path) ?? trail?.find((p) => p.path === path);
      const r = byPath.get(path);
      go(known ?? ({ path, name: r?.name ?? path, code: r?.code ?? "", label: r?.code ?? "" } as DrillDownPoint));
    },
    [go, parts, trail, byPath]
  );

  // At the lowest level the region's own units, largest first by the primary.
  const { data: leafUnits } = useSWR(
    validOn && isLeaf ? ["drilldown-map:units", unitType, at, activityCategory?.path ?? "", validOn, primary.key] : null,
    () => readRegionUnits(unitType, at, activityCategory?.path ?? null, validOn!, primary.key),
    { revalidateOnFocus: false }
  );

  const features = useMemo<GeoJSON.FeatureCollection<GeoJSON.Point>>(() => {
    const placed = isLeaf
      ? [{ path: at, total: 1, label: "" }]
      : parts.map((r) => ({ path: r.path, total: valueOf(r, primary.key), label: whole(valueOf(r, primary.key)) }));
    return {
      type: "FeatureCollection",
      features: placed.flatMap((p) => {
        const g = byPath.get(p.path);
        if (g?.latitude == null || g.longitude == null) return [];
        return [
          {
            type: "Feature" as const,
            geometry: { type: "Point" as const, coordinates: [Number(g.longitude), Number(g.latitude)] },
            properties: { path: p.path, name: g.name, total: p.total, figures: p.label },
          },
        ];
      }),
    };
  }, [parts, primary, byPath, isLeaf, at]);

  // Frames every circle of the level.
  const featuresRef = useRef(features);
  const fitRef = useRef(() => {});
  useGuardedEffect(
    () => {
      featuresRef.current = features;
      fitRef.current = () => {
        const map = mapRef.current;
        const b = featureBounds(featuresRef.current.features as never);
        if (!map || !b) return;
        const [w, s, e, n] = b;
        if (e - w < 0.01 && n - s < 0.01) map.easeTo({ center: [w, s], zoom: 9 });
        else map.fitBounds(b, { padding: 60, maxZoom: 10 });
      };
    },
    [features],
    "RegionMap:fit"
  );

  const onReady = useCallback((map: MapLibreMap) => {
    mapRef.current = map;
    map.doubleClickZoom.disable();
    map.addSource("regions", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addSource("ringed", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addLayer({
      id: "region-circles",
      type: "circle",
      source: "regions",
      layout: { "circle-sort-key": ["-", 0, ["get", "total"]] },
      paint: {
        "circle-color": cssColour("--color-enterprise-500"),
        "circle-opacity": 0.75,
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 1.5,
        "circle-radius": 6,
      },
    });
    map.addLayer({
      id: "ringed-ring",
      type: "circle",
      source: "ringed",
      paint: { "circle-color": "rgba(0,0,0,0)", "circle-radius": 10, "circle-stroke-color": "#111827", "circle-stroke-width": 3 },
    });
    map.addLayer({
      id: "region-labels",
      type: "symbol",
      source: "regions",
      layout: {
        "text-field": ["format", ["get", "name"], { "text-font": ["literal", BASEMAP_FONT_BOLD] }, "\n", {}, ["get", "figures"], {}],
        "text-font": BASEMAP_FONT,
        "text-size": 13,
        "text-variable-anchor": ["top", "right"],
        "text-radial-offset": 1.2,
        "symbol-sort-key": ["-", 0, ["get", "total"]],
      },
      paint: { "text-color": "#111827", "text-halo-color": "#ffffff", "text-halo-width": 2.5 },
    });
    map.on("mouseenter", "region-circles", () => (map.getCanvas().style.cursor = "pointer"));
    map.on("mouseleave", "region-circles", () => (map.getCanvas().style.cursor = ""));
    // Fits the view to every circle shown, as the Regions map's button does.
    map.addControl(
      new ViewControl([{ title: "Show all the regions here", icon: "⤢", onClick: () => fitRef.current() }]),
      "top-left"
    );
    setMapReady(true);
  }, []);

  // The map follows its box, not only the window: the page widens when the map is flipped in
  // and narrows on the way back, after the map has been drawn.
  const boxRef = useRef<HTMLDivElement>(null);
  useGuardedEffect(
    () => {
      const box = boxRef.current;
      if (!box || !mapReady) return;
      const observer = new ResizeObserver(() => mapRef.current?.resize());
      observer.observe(box);
      return () => observer.disconnect();
    },
    [mapReady],
    "RegionMap:resize"
  );

  // As on the search map: a click on a circle rings it and marks its row; a double click goes in.
  const handlers = useRef({ ring: setRinged, goPath });
  useGuardedEffect(
    () => {
      handlers.current = { ring: setRinged, goPath };
    },
    [goPath, setRinged],
    "RegionMap:handlers"
  );
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      const onClick = (e: MapLayerMouseEvent) => {
        const f = map.queryRenderedFeatures(e.point, { layers: ["region-circles"] })[0];
        handlers.current.ring((f?.properties?.path as string | undefined) ?? null);
      };
      const onDouble = (e: MapLayerMouseEvent) => {
        const path = e.features?.[0]?.properties?.path as string | undefined;
        if (path) handlers.current.goPath(path);
      };
      map.on("click", onClick);
      map.on("dblclick", "region-circles", onDouble);
      return () => {
        map.off("click", onClick);
        map.off("dblclick", "region-circles", onDouble);
      };
    },
    [mapReady],
    "RegionMap:clicks"
  );

  const framed = useRef<string | null>(null);
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(features);
      (map.getSource("ringed") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: features.features.filter((f) => f.properties?.path === ringed),
      });
      map.setPaintProperty("region-circles", "circle-color", cssColour(`--color-${unitType}-500`));
      const max = Math.max(1, ...features.features.map((f) => Number(f.properties?.total ?? 0)));
      map.setPaintProperty("region-circles", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["max", 0, ["get", "total"]]], 0, 4, Math.sqrt(max), 28]);
      map.setLayoutProperty("region-labels", "text-radial-offset", ["interpolate", ["linear"], ["sqrt", ["max", 0, ["get", "total"]]], 0, 8 / 13, Math.sqrt(max), 32 / 13]);
      map.setLayoutProperty("region-labels", "visibility", isLeaf ? "none" : "visible");
      // Frames a new level once its own parts are drawn.
      if (features.features.length > 0 && framed.current !== at) {
        framed.current = at;
        fitRef.current();
      }
    },
    [features, mapReady, unitType, at, ringed, isLeaf],
    "RegionMap:draw"
  );

  // The units behind a figure in Search: the place, the activity, the unit type, sorted by the
  // primary variable, largest first, so the list opens on the units that make the total.
  const searchHref = (path: string) => {
    const q = new URLSearchParams();
    if (path) q.set(REGION, path);
    if (activityCategory) q.set(ACTIVITY_CATEGORY_PATH, activityCategory.path);
    q.set(UNIT_TYPE, unitType);
    if (primary.key !== "count") q.set("order", `${primary.key}.desc.nullslast`);
    return `/search?${q}`;
  };
  // Leaves the Drilldown for Search's list of those units: the box-with-arrow-out icon.
  const searchLink = (path: string, label: string) => (
    <Link
      href={searchHref(path)}
      className="rounded p-1 text-gray-400 hover:bg-gray-200 hover:text-gray-900"
      title={`Open ${label} in Search`}
      aria-label={`Open ${label} in Search`}
      data-drilldown-map-search={path}
    >
      <SquareArrowOutUpRight className="h-4 w-4" />
    </Link>
  );
  // A figure; a variable's tooltip gives its mean over the units that report it. Shares are read
  // from the bars, whose lengths show them better than a percentage (owner 2026-11-28 14:46).
  const cell = (m: Measure, f: Figures) => {
    const value = valueOf(f, m.key);
    const n = reportingOf(f, m.key);
    return (
      <td
        key={m.key}
        className={`py-1 pl-3 text-right tabular-nums ${m.key === primary.key ? "font-medium" : ""}`}
        title={n !== undefined ? (n > 0 ? `mean ${oneDecimal(value / n)} over the ${whole(n)} of ${whole(f.count)} that report it` : "no unit reports it") : undefined}
      >
        {whole(value)}
      </td>
    );
  };
  const parentPath = parentOf(at);

  return (
    // Side by side from md up: a square map, as tall as the window allows, and the table beside
    // it in the rest, at its full height, so the page scrolls rather than a box inside it; the
    // map stays in view. On a narrow screen the map sits above the table.
    <div className="flex flex-col rounded border bg-white md:flex-row md:items-start" data-drilldown-region-map="">
      <div
        ref={boxRef}
        className="relative h-[50vh] min-w-0 md:sticky md:top-0 md:aspect-square md:h-auto md:w-[min(75vh,60%)] md:shrink-0"
      >
        <UnitMap onReady={onReady} className="absolute inset-0" />
      </div>
      <div className="min-w-0 flex-1 space-y-3 self-stretch overflow-x-auto border-t p-3 text-sm md:min-w-[24rem] md:border-l md:border-t-0">
        {selection && selection.count === 0 && !isLeaf && <MapEmptyNote frameName={frameName} />}
        {/* One table: the selection's own row on top, framed, then its parts, largest first by
            the primary. Comparing regions is reading down a column. */}
        <table className="w-full border-collapse" data-drilldown-map-table="">
          <thead>
            <tr className="text-xs text-gray-500">
              <th className="pb-1 text-left font-medium uppercase tracking-wide">
                {at ? "Selected region" : "Selected country"}
              </th>
              {measures.map((m) => (
                <th key={m.key} className={`pb-1 pl-3 text-right font-medium ${m.key === primary.key ? "text-gray-900" : ""}`}>
                  {m.label}
                </th>
              ))}
              <th className="w-14" />
            </tr>
          </thead>
          <tbody>
            <tr className="border-2 border-gray-900 bg-gray-50" data-drilldown-map-selection="">
              <td className="py-1.5 pl-2 font-medium">
                {nameOf(at)}
                {at && <span className="ml-1.5 text-xs font-normal text-gray-500">{byPath.get(at)?.code ?? at}</span>}
              </td>
              {selection
                ? measures.map((m) => cell(m, selection))
                : measures.map((m) => (
                    <td key={m.key} className="py-1.5 pl-3 text-right text-xs text-gray-500">
                      {isLoading ? "…" : ""}
                    </td>
                  ))}
              <td className="pr-1 text-right">
                <span className="flex items-center justify-end">
                  {searchLink(at, `the ${unitsLabel.toLowerCase()} of ${nameOf(at)}`)}
                  {at && (
                    <button
                      type="button"
                      className="rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                      title={`Back to ${nameOf(parentPath)}`}
                      aria-label={`Back to ${nameOf(parentPath)}`}
                      onClick={() => goPath(parentPath)}
                    >
                      <X className="h-4 w-4" />
                    </button>
                  )}
                </span>
              </td>
            </tr>
            {!isLeaf && parts.length > 0 && (
              <tr>
                <td colSpan={measures.length + 2} className="pt-3 text-xs font-medium uppercase tracking-wide text-gray-500">
                  {parts.length} {at ? "subregions" : "regions"}, largest {primary.label.toLowerCase()} first
                </td>
              </tr>
            )}
            {/* As on the search map and the Regions map: a row click goes in, so it becomes the
                selection; the eye only rings the region's circle on the map. */}
            {parts.map((r) => (
              <tr
                key={r.path}
                className={`cursor-pointer ${r.path === ringed ? "bg-gray-100" : "hover:bg-gray-50"}`}
                onClick={() => go(r)}
                title={`Go into ${r.name}`}
                data-drilldown-map-row={r.path}
              >
                <td className="max-w-[16rem] truncate py-1 pl-2">{r.name}</td>
                {measures.map((m) => cell(m, r))}
                <td className="pr-1 text-right" onClick={(e) => e.stopPropagation()}>
                  <span className="flex items-center justify-end">
                    <button
                      type="button"
                      className={`rounded p-1 hover:bg-gray-200 hover:text-gray-900 ${r.path === ringed ? "text-gray-900" : "text-gray-400"}`}
                      title={r.path === ringed ? `Stop showing where ${r.name} is` : `Show where ${r.name} is`}
                      aria-pressed={r.path === ringed}
                      onClick={() => setRinged(r.path === ringed ? null : r.path)}
                    >
                      <Eye className="h-4 w-4" />
                    </button>
                    {searchLink(r.path, `the ${unitsLabel.toLowerCase()} of ${r.name}`)}
                  </span>
                </td>
              </tr>
            ))}
            {/* At the lowest level the region's units are its parts: rows of the same table,
                under the same headings. A unit counts once in the units column. */}
            {isLeaf && (
              <tr>
                <td colSpan={measures.length + 1} className="pt-3 text-xs font-medium uppercase tracking-wide text-gray-500" data-drilldown-map-units="">
                  {primary.key === "count"
                    ? `The first ${unitsLabel.toLowerCase()} by name`
                    : `Largest ${unitsLabel.toLowerCase()} by ${primary.label.toLowerCase()}`}
                </td>
                <td className="pr-1 pt-3 text-right">
                  <span className="flex justify-end">{searchLink(at, `all the ${unitsLabel.toLowerCase()} of ${nameOf(at)}`)}</span>
                </td>
              </tr>
            )}
            {isLeaf &&
              (leafUnits ?? []).map((u) => {
                const figures: Figures = { count: 1, stats_summary: (u.stats_summary ?? {}) as Figures["stats_summary"] };
                return (
                  <tr key={`${u.unit_type}:${u.unit_id}`} data-drilldown-map-unit={`${u.unit_type}:${u.unit_id}`}>
                    <td className="max-w-[16rem] truncate py-0.5 pl-2" title={u.name}>{u.name}</td>
                    {measures.map((m) => cell(m, figures))}
                    {/* Opens the unit's own statistical variables, the page that matches what
                        this view shows. It leaves the Drilldown, so the box-out icon. */}
                    <td className="pr-1 text-right">
                      <span className="flex justify-end">
                        <Link
                          href={`/${UNIT_PATH[u.unit_type as MapUnitType]}/${u.unit_id}/statistical-variables`}
                          className="rounded p-1 text-gray-400 hover:bg-gray-200 hover:text-gray-900"
                          title={`Open ${u.name}'s statistical variables`}
                          aria-label={`Open ${u.name}'s statistical variables`}
                          data-drilldown-map-unit-link={`${u.unit_type}:${u.unit_id}`}
                        >
                          <SquareArrowOutUpRight className="h-4 w-4" />
                        </Link>
                      </span>
                    </td>
                  </tr>
                );
              })}
          </tbody>
        </table>
        {!isLeaf && parts.length === 0 && isLoading && <MapPanelSkeleton rows={8} />}
        {isLeaf && !leafUnits && <MapPanelSkeleton rows={8} />}
      </div>
    </div>
  );
}
