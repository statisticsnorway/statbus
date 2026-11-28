"use client";

// Reports → Map (ppvxg2): statistical variables by region. One selection, where you are; the map
// draws its parts sized by one measure; every figure is in the side panel's table (owner
// 2026-11-27 21:21, the simpler model, tried against branch explore/ppvxg2-spider-and-side-box).
// The Read picker compares two ways to read (tmp/ppvxg2-proto.md) until one is chosen.
import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { Eye, SquareArrowOutUpRight, X } from "lucide-react";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { useTimeFrame } from "@/atoms/app-derived";
import { statDefinitionsAtom } from "@/atoms/base-data";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "@/components/map/unit-map";
import { BASEMAP_FONT, BASEMAP_FONT_BOLD } from "@/components/map/basemap";
import { featureBounds, UNIT_PATH, type MapUnitType } from "@/components/map/map-data";
import { ViewControl } from "@/components/map/view-control";
import { REGION, UNIT_TYPE } from "@/app/search/filters/url-search-params";
import { UnitTypeTabs, getUnitTypeLabel } from "../unit-type-tabs";
import { readMeasures, readRegionUnits, type ReadStrategy, type RegionMeasures } from "./read";
import { MeasurePicker } from "./measure-picker";
import { MapEmptyNote, MapPanelSkeleton } from "@/components/map/map-panel-states";

interface MapRegion {
  path: string;
  code: string | null;
  name: string;
  latitude: number | null;
  longitude: number | null;
}

/** A column of the table: the number of units, or a variable's total. */
interface Column {
  key: string;
  label: string;
  valueOf: (r: RegionMeasures) => number;
  /** How many units carry the value; none for the number of units itself. */
  countOf?: (r: RegionMeasures) => number;
}

const parentOf = (p: string) => p.split(".").slice(0, -1).join(".");
const whole = (x: number) => Math.round(x).toLocaleString("en");
const oneDecimal = (x: number) => x.toLocaleString("en", { maximumFractionDigits: 1 });

export default function ReportsMapPage() {
  const client = useAtomValue(restClientAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const [strategy, setStrategy] = useState<ReadStrategy>("Cp");
  const [unitType, setUnitType] = useState<UnitType>("enterprise");
  // The measures shown as columns ("units" and variable codes) and the primary one, which sizes
  // the circles and orders the table (owner 2026-11-27 20:40).
  const [sizeBy, setSizeBy] = useState("units");
  const [shownMeasures, setShownMeasures] = useState<string[]>(["units"]);
  // The selection: where you are, "" for the country. The map and the table show its parts.
  const [at, setAt] = useState("");
  // The part the eye rings on the map; it only locates, it is not a second selection.
  const [ringed, setRinged] = useState<string | null>(null);
  // Each figure also as a share of the selection's own.
  const [showShare, setShowShare] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const [mapReady, setMapReady] = useState(false);

  // Only variables that are summed (int, float) add up over the units of a region.
  const variables = useMemo(
    () =>
      statDefinitions
        .filter((d) => d.code && (d.type === "int" || d.type === "float"))
        .map((d) => ({ code: d.code!, name: d.name ?? d.code! })),
    [statDefinitions]
  );
  const unitsLabel = getUnitTypeLabel(unitType) ?? "Units";
  // The columns: the primary first, then the others in the pills' order.
  const columns = useMemo<Column[]>(() => {
    const all: Column[] = [
      { key: "units", label: unitsLabel, valueOf: (r) => r.units },
      ...variables.map((v) => ({
        key: v.code,
        label: v.name,
        valueOf: (r: RegionMeasures) => r.totals[v.code]?.sum ?? 0,
        countOf: (r: RegionMeasures) => r.totals[v.code]?.count ?? 0,
      })),
    ];
    // The primary first, then the others in the order they were added, so the one a fourth would
    // replace (MeasurePicker's cap, first in first out) is the leftmost after the primary.
    const byKey = new Map(all.map((c) => [c.key, c]));
    const others = shownMeasures.filter((k) => k !== sizeBy).flatMap((k) => byKey.get(k) ?? []);
    return [...(byKey.get(sizeBy) ? [byKey.get(sizeBy)!] : []), ...others];
  }, [variables, unitsLabel, sizeBy, shownMeasures]);
  const primary = columns[0];
  // The variables read: those among the columns.
  const codes = useMemo(() => columns.filter((c) => c.key !== "units").map((c) => c.key), [columns]);

  const { data: countryName } = useSWR(client ? ["reports-map:country"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(name)").limit(1).single();
    if (error) throw error;
    return (data.country as { name: string } | null)?.name ?? null;
  });
  const { data: regions } = useSWR(client ? ["reports-map:regions"] : null, async () => {
    const { data, error } = await client!
      .from("region")
      .select("path,code,name,latitude,longitude")
      .order("path");
    if (error) throw error;
    return (data ?? []) as MapRegion[];
  });
  const byPath = useMemo(() => new Map((regions ?? []).map((r) => [r.path, r])), [regions]);
  const hasChildren = useMemo(() => new Set((regions ?? []).map((r) => parentOf(r.path))), [regions]);
  const isLeaf = at !== "" && !hasChildren.has(at);
  const nameOf = useCallback(
    (p: string) => (p ? (byPath.get(p)?.name ?? p) : (countryName ?? "Country")),
    [byPath, countryName]
  );

  // The selection's parts; at the lowest level, read from one level up for the selection's own row.
  const { data: read, error, isLoading } = useSWR(
    regions && validOn ? ["reports-map:read", strategy, unitType, isLeaf ? parentOf(at) : at, validOn, codes.join(",")] : null,
    () => readMeasures(strategy, unitType, isLeaf ? parentOf(at) : at, validOn!, codes),
    { revalidateOnFocus: false, keepPreviousData: true }
  );
  const { data: parentRead } = useSWR(
    regions && validOn && at && !isLeaf
      ? ["reports-map:read", strategy, unitType, parentOf(at), validOn, codes.join(",")]
      : null,
    () => readMeasures(strategy, unitType, parentOf(at), validOn!, codes),
    { revalidateOnFocus: false }
  );
  // Figures only from a read of the columns now shown: a kept earlier read lacks a newly checked
  // one, which would show as 0 rather than as not read yet.
  const current = (rows: RegionMeasures[] | undefined) =>
    !!rows && (rows.length === 0 || codes.every((c) => c in rows[0].totals));
  const parts = useMemo(
    () => (isLeaf || !current(read?.rows) ? [] : [...read!.rows].sort((a, b) => primary.valueOf(b) - primary.valueOf(a))),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- current reads codes, listed
    [read, primary, isLeaf, codes]
  );
  // The selection's own figures: the country is the sum of its parts; a region is its row one up.
  const selectionRow = useMemo<RegionMeasures | null>(() => {
    if (!at) {
      if (!current(read?.rows)) return null;
      return read!.rows.reduce<RegionMeasures>(
        (acc, r) => {
          acc.units += r.units;
          for (const c of codes) {
            const t = acc.totals[c] ?? { sum: 0, count: 0 };
            t.sum += r.totals[c]?.sum ?? 0;
            t.count += r.totals[c]?.count ?? 0;
            acc.totals[c] = t;
          }
          return acc;
        },
        { path: "", units: 0, totals: {} }
      );
    }
    const rows = isLeaf ? read?.rows : parentRead?.rows;
    return current(rows) ? (rows!.find((r) => r.path === at) ?? null) : null;
    // eslint-disable-next-line react-hooks/exhaustive-deps -- current reads codes, listed
  }, [at, isLeaf, read, parentRead, codes]);

  // At the lowest level the region's own units, largest first by the primary.
  const { data: leafUnits } = useSWR(
    validOn && isLeaf ? ["reports-map:units", unitType, at, validOn, sizeBy] : null,
    () => readRegionUnits(unitType, at, validOn!, sizeBy),
    { revalidateOnFocus: false }
  );

  const features = useMemo<GeoJSON.FeatureCollection<GeoJSON.Point>>(() => {
    const placed: { path: string; total: number; label: string }[] = isLeaf
      ? [{ path: at, total: 1, label: "" }]
      : parts.map((r) => ({ path: r.path, total: primary.valueOf(r), label: whole(primary.valueOf(r)) }));
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

  const go = useCallback((path: string) => {
    setRinged(null);
    setAt(path);
  }, []);

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
    "ReportsMap:fit"
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

  // As on the search map: a click on a circle rings it and marks its row; a double click goes in.
  const handlers = useRef({ ring: setRinged, go });
  useGuardedEffect(
    () => {
      handlers.current = { ring: setRinged, go };
    },
    [go],
    "ReportsMap:handlers"
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
        if (path) handlers.current.go(path);
      };
      map.on("click", onClick);
      map.on("dblclick", "region-circles", onDouble);
      return () => {
        map.off("click", onClick);
        map.off("dblclick", "region-circles", onDouble);
      };
    },
    [mapReady],
    "ReportsMap:clicks"
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
      // Frames a new level once its own parts are drawn: a kept read of the level before (SWR keeps
      // the previous data while the new one loads) would frame the old circles and stop there.
      const levelRead = isLeaf || features.features.every((f) => parentOf(String(f.properties?.path)) === at);
      if (features.features.length > 0 && levelRead && framed.current !== at) {
        framed.current = at;
        fitRef.current();
      }
    },
    [features, mapReady, unitType, at, ringed, isLeaf],
    "ReportsMap:draw"
  );

  const trail = ["", ...(at ? at.split(".").map((_, i, a) => a.slice(0, i + 1).join(".")) : [])];
  // The units behind a figure in Search: the place, the unit type, and sorted by the primary
  // variable, largest first, so the list opens on the units that make the total.
  const searchHref = (path: string) => {
    const q = new URLSearchParams();
    if (path) q.set(REGION, path);
    q.set(UNIT_TYPE, unitType);
    if (sizeBy !== "units") q.set("order", `${sizeBy}.desc.nullslast`);
    return `/search?${q}`;
  };
  // Leaves this map for Search's list of those units: the box-with-arrow-out icon (owner
  // 2026-11-27 20:32: a list icon is for this same view's own list, as on the search map).
  const searchLink = (path: string, label: string) => (
    <Link
      href={searchHref(path)}
      className="rounded p-1 text-gray-400 hover:bg-gray-200 hover:text-gray-900"
      title={`Open ${label} in Search`}
      aria-label={`Open ${label} in Search`}
      data-reports-map-search={path}
    >
      <SquareArrowOutUpRight className="h-4 w-4" />
    </Link>
  );
  // A figure, with its share of the selection's own when asked; a variable's tooltip gives its
  // mean over the units that report it.
  const cell = (c: Column, r: RegionMeasures) => {
    const value = c.valueOf(r);
    const n = c.countOf?.(r);
    const share = selectionRow && c.valueOf(selectionRow) > 0 ? (100 * value) / c.valueOf(selectionRow) : null;
    return (
      <td
        key={c.key}
        className={`py-1 pl-3 text-right tabular-nums ${c.key === sizeBy ? "font-medium" : ""}`}
        title={n !== undefined ? (n > 0 ? `mean ${oneDecimal(value / n)} over the ${whole(n)} of ${whole(r.units)} that report it` : "no unit reports it") : undefined}
      >
        {whole(value)}
        {showShare && share !== null && r !== selectionRow && (
          <span className="block text-xs font-normal text-gray-500">{oneDecimal(share)}%</span>
        )}
      </td>
    );
  };

  return (
    <main className="flex flex-col gap-3" data-reports-map="">
      {/* Titled as its siblings are ("Statistical variables over time"): what it shows, then how
          (owner 2026-11-27 20:36: the map's purpose is the statistical variables). */}
      <header>
        <h1 className="mb-3 text-2xl">Map: Statistical variables by region</h1>
        <p className="text-gray-600">
          Where the units are and where their totals lie, region by region, for enterprises, legal
          units or establishments
        </p>
      </header>
      {/* The unit type first: it decides what the measures below count (owner 2026-11-27 20:34). */}
      <UnitTypeTabs value={unitType} onValueChange={setUnitType} />
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
        <MeasurePicker
          measures={[{ key: "units", label: unitsLabel }, ...variables.map((v) => ({ key: v.code, label: v.name }))]}
          selected={shownMeasures}
          primary={sizeBy}
          onSelected={setShownMeasures}
          onPrimary={setSizeBy}
        />
      </div>
      {error && <p className="text-sm text-red-600" data-reports-map-error="">{String(error.message ?? error)}</p>}
      {/* Side by side from md up: the table takes the width its columns need (up to half) and
          its full height, so the page scrolls rather than a box inside it; the map stays in view
          beside it. On a narrow screen the map sits above the table. */}
      <div className="flex flex-col rounded border md:flex-row md:items-start">
        <div className="relative h-[50vh] min-w-0 md:sticky md:top-0 md:h-[80vh] md:flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
        </div>
        <aside
          className="flex flex-col self-stretch border-t text-sm md:w-auto md:min-w-[24rem] md:max-w-[50%] md:shrink-0 md:border-l md:border-t-0"
          data-reports-map-side=""
        >
          <div className="flex-1 space-y-3 overflow-x-auto p-3">
            <nav aria-label="Region trail" className="flex flex-wrap items-center gap-1" data-reports-map-trail="">
              {trail.map((p, i) => (
                <span key={p || "country"} className="flex items-center gap-1">
                  {i > 0 && <span className="text-gray-400">›</span>}
                  {i === trail.length - 1 ? (
                    <span className="font-medium" aria-current="location">{nameOf(p)}</span>
                  ) : (
                    <button type="button" className="underline-offset-2 hover:underline" onClick={() => go(p)}>
                      {nameOf(p)}
                    </button>
                  )}
                </span>
              ))}
            </nav>
            {/* The selection's figures read but none in the frame: said in words, not as zeros. */}
            {selectionRow && selectionRow.units === 0 && !isLeaf && (
              <MapEmptyNote frameName={selectedTimeFrame?.name ?? null} />
            )}
            {/* One table: the selection's own row on top, framed as the Selected box, then its
                parts, largest first by the primary. Comparing regions is reading down a column. */}
            <table className="w-full border-collapse" data-reports-map-table="">
              <thead>
                <tr className="text-xs text-gray-500">
                  <th className="pb-1 text-left font-medium uppercase tracking-wide">
                    {at ? "Selected region" : "Selected country"}
                  </th>
                  {columns.map((c) => (
                    <th key={c.key} className={`pb-1 pl-3 text-right font-medium ${c.key === sizeBy ? "text-gray-900" : ""}`}>
                      {c.label}
                    </th>
                  ))}
                  <th className="w-14" />
                </tr>
              </thead>
              <tbody>
                <tr className="border-2 border-gray-900 bg-gray-50" data-reports-map-selection="">
                  <td className="py-1.5 pl-2 font-medium">
                    <span className="flex items-center gap-1.5">
                      <span>
                        {nameOf(at)}
                        {at && <span className="ml-1.5 text-xs font-normal text-gray-500">{byPath.get(at)?.code ?? at}</span>}
                      </span>
                      {/* A quiet % beside the selection (owner 2026-11-28 13:50): pressed, every
                          figure inside it also shows its share of the selection's own. */}
                      <button
                        type="button"
                        className={`rounded px-1 text-xs font-semibold leading-5 ${
                          showShare ? "bg-gray-900 text-white" : "text-gray-400 hover:bg-gray-200 hover:text-gray-900"
                        }`}
                        aria-pressed={showShare}
                        title={showShare ? `Hide the shares of ${nameOf(at)}` : `Show each figure as a share of ${nameOf(at)}`}
                        onClick={() => setShowShare((s) => !s)}
                        data-reports-map-share=""
                      >
                        %
                      </button>
                    </span>
                  </td>
                  {selectionRow
                    ? columns.map((c) => cell(c, selectionRow))
                    : columns.map((c) => (
                        <td key={c.key} className="py-1.5 pl-3 text-right text-xs text-gray-500">
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
                          title={`Back to ${nameOf(parentOf(at))}`}
                          aria-label={`Back to ${nameOf(parentOf(at))}`}
                          onClick={() => go(parentOf(at))}
                        >
                          <X className="h-4 w-4" />
                        </button>
                      )}
                    </span>
                  </td>
                </tr>
                {!isLeaf && parts.length > 0 && (
                  <tr>
                    <td colSpan={columns.length + 2} className="pt-3 text-xs font-medium uppercase tracking-wide text-gray-500">
                      {parts.length} {at ? "subregions" : "regions"}, largest {primary.label.toLowerCase()} first
                    </td>
                  </tr>
                )}
                {/* As on the search map and the Regions map: a row click goes in, so it becomes
                    the selection; the eye only rings the region's circle on the map. */}
                {parts.map((r) => (
                  <tr
                    key={r.path}
                    className={`cursor-pointer ${r.path === ringed ? "bg-gray-100" : "hover:bg-gray-50"}`}
                    onClick={() => go(r.path)}
                    title={`Go into ${nameOf(r.path)}`}
                    data-child-row={r.path}
                  >
                    <td className="max-w-[16rem] truncate py-1 pl-2">{nameOf(r.path)}</td>
                    {columns.map((c) => cell(c, r))}
                    <td className="pr-1 text-right" onClick={(e) => e.stopPropagation()}>
                      <span className="flex items-center justify-end">
                        <button
                          type="button"
                          className={`rounded p-1 hover:bg-gray-200 hover:text-gray-900 ${r.path === ringed ? "text-gray-900" : "text-gray-400"}`}
                          title={r.path === ringed ? `Stop showing where ${nameOf(r.path)} is` : `Show where ${nameOf(r.path)} is`}
                          aria-pressed={r.path === ringed}
                          onClick={() => setRinged(r.path === ringed ? null : r.path)}
                        >
                          <Eye className="h-4 w-4" />
                        </button>
                        {searchLink(r.path, `the ${unitsLabel.toLowerCase()} of ${nameOf(r.path)}`)}
                      </span>
                    </td>
                  </tr>
                ))}
                {/* At the lowest level the region's units are its parts: rows of the same table,
                    under the same headings (owner 2026-11-27 22:49: in a table of their own the
                    columns did not line up). A unit counts once in the units column. */}
                {isLeaf && (
                  <tr>
                    <td colSpan={columns.length + 1} className="pt-3 text-xs font-medium uppercase tracking-wide text-gray-500" data-reports-map-units="">
                      {sizeBy === "units" ? `The first ${unitsLabel.toLowerCase()} by name` : `Largest ${unitsLabel.toLowerCase()} by ${primary.label.toLowerCase()}`}
                    </td>
                    <td className="pr-1 pt-3 text-right">
                      <span className="flex justify-end">{searchLink(at, `all the ${unitsLabel.toLowerCase()} of ${nameOf(at)}`)}</span>
                    </td>
                  </tr>
                )}
                {isLeaf &&
                  (leafUnits ?? []).map((u) => (
                    <tr key={`${u.unit_type}:${u.unit_id}`} data-reports-map-unit={`${u.unit_type}:${u.unit_id}`}>
                      <td className="max-w-[16rem] truncate py-0.5 pl-2" title={u.name}>{u.name}</td>
                      {columns.map((c) => {
                        const s = c.key === "units" ? null : u.stats_summary?.[c.key];
                        const value =
                          c.key === "units" ? 1 : s && typeof s === "object" && s.sum != null ? Number(s.sum) : null;
                        // A unit's share of the region's own total, so the % switch means the same
                        // at every level (owner 2026-11-27 22:47).
                        const regionTotal = selectionRow ? c.valueOf(selectionRow) : 0;
                        return (
                          <td key={c.key} className={`py-0.5 pl-3 text-right tabular-nums ${c.key === sizeBy ? "font-medium" : ""}`}>
                            {value !== null ? whole(value) : "–"}
                            {showShare && value !== null && regionTotal > 0 && (
                              <span className="block text-xs font-normal text-gray-500">{oneDecimal((100 * value) / regionTotal)}%</span>
                            )}
                          </td>
                        );
                      })}
                      {/* Opens the unit's own statistical variables, the page that matches what this
                          map shows (owner 2026-11-27 22:50). It leaves the map, so the box-out icon. */}
                      <td className="pr-1 text-right">
                        <span className="flex justify-end">
                          <Link
                            href={`/${UNIT_PATH[u.unit_type as MapUnitType]}/${u.unit_id}/statistical-variables`}
                            className="rounded p-1 text-gray-400 hover:bg-gray-200 hover:text-gray-900"
                            title={`Open ${u.name}'s statistical variables`}
                            aria-label={`Open ${u.name}'s statistical variables`}
                            data-reports-map-unit-link={`${u.unit_type}:${u.unit_id}`}
                          >
                            <SquareArrowOutUpRight className="h-4 w-4" />
                          </Link>
                        </span>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
            {/* While the parts are read the table's body pulses, as the search list does (owner
                2026-11-27 22:25: loading and no data looked the same). */}
            {!isLeaf && parts.length === 0 && !current(read?.rows) && !error && <MapPanelSkeleton rows={8} />}
            {isLeaf && !leafUnits && <MapPanelSkeleton rows={8} />}
          </div>
          {/* While the read is chosen: which read, and what it cost. */}
          <div className="flex items-center gap-2 border-t p-2 text-xs text-gray-500" data-reports-map-timing="">
            <select aria-label="Read" className="rounded border px-1 py-0.5" value={strategy} onChange={(e) => setStrategy(e.target.value as ReadStrategy)}>
              <option value="B">B facet sums</option>
              <option value="Cp">C′ region rows</option>
            </select>
            <span className="font-mono" title={read?.url}>
              {isLoading ? "reading…" : read ? `${read.ms} ms, ${Math.round(read.bytes / 1024)} KB` : ""}
            </span>
            <span className="ml-auto">valid on {validOn ?? "…"}</span>
          </div>
        </aside>
      </div>
    </main>
  );
}
