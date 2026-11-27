"use client";

// Reports → Map (ppvxg2), being prototyped with the owner: the regions sized by a number of units
// or a variable's total, several variables at a region as a spider, the units of a region at the
// lowest level. The Read picker compares two ways to read (tmp/ppvxg2-proto.md) until one is chosen.
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
import { featureBounds } from "@/components/map/map-data";
import { ViewControl } from "@/components/map/view-control";
import { REGION, UNIT_TYPE } from "@/app/search/filters/url-search-params";
import { UnitTypeTabs, getUnitTypeLabel } from "../unit-type-tabs";
import {
  readMeasures,
  readRegionUnits,
  readTypeTotals,
  type ReadStrategy,
  type RegionMeasures,
} from "./read";
import { VariableSpider, type SpiderMeasure } from "./variable-spider";
import { MeasurePicker } from "./measure-picker";

interface MapRegion {
  path: string;
  code: string | null;
  name: string;
  latitude: number | null;
  longitude: number | null;
}

interface Variable {
  code: string;
  name: string;
}

const parentOf = (p: string) => p.split(".").slice(0, -1).join(".");
const depthOf = (p: string) => (p ? p.split(".").length : 0);
const whole = (x: number) => Math.round(x).toLocaleString("en");
const compactNumber = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });
const mean = (x: number) => x.toLocaleString("en", { maximumFractionDigits: 1 });
/** The colours of the spider's nodes: the unit type's for the count, then one per variable. */
const VARIABLE_COLOURS = ["#0f766e", "#b45309", "#7c3aed", "#be123c", "#1d4ed8"];

/**
 * Zoom bands of the region levels when zoom drives the level (owner 2026-11-27: tried on this map
 * only, off until it proves itself): the country's top regions below zoom 6, one level deeper per
 * 1.5 zoom steps after that.
 */
const levelForZoom = (zoom: number) => (zoom < 6 ? 0 : 1 + Math.floor((zoom - 6) / 1.5));
/** The zooms at which levelForZoom gives `depth`, as [from, to]. */
const zoomBand = (depth: number): [number, number] =>
  depth === 0 ? [1, 5.9] : [6 + 1.5 * (depth - 1), 6 + 1.5 * depth - 0.1];

export default function ReportsMapPage() {
  const client = useAtomValue(restClientAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const [strategy, setStrategy] = useState<ReadStrategy>("Cp");
  const [unitType, setUnitType] = useState<UnitType>("enterprise");
  // The measures shown ("units" and variable codes) and the primary one that sizes the circles
  // (owner 2026-11-27 20:30: picked like the unit types, one marked primary).
  const [sizeBy, setSizeBy] = useState("units");
  const [shownMeasures, setShownMeasures] = useState<string[]>(["units"]);
  const [at, setAt] = useState("");
  const [picked, setPicked] = useState<string | null>(null);
  const [zoomDrives, setZoomDrives] = useState(false);
  // Where the picked region's figures show, two ways explored side by side (owner 2026-11-27
  // 20:30): as a spider round its circle on the map, or as a third part of the side panel beside
  // the selection's own figures.
  const [compareIn, setCompareIn] = useState<"map" | "side">("map");
  // Erik's ideas from PR #325, each a switch while we explore them (owner 2026-11-27 17:35).
  const [labelAll, setLabelAll] = useState(false);
  const [typeSideBySide, setTypeSideBySide] = useState(false);
  const [unitCards, setUnitCards] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const [mapReady, setMapReady] = useState(false);
  // The map as state too, for the spider drawn over it during render.
  const [mapInstance, setMapInstance] = useState<MapLibreMap | null>(null);

  // Only variables that are summed (int, float) add up over the units of a region.
  const variables = useMemo<Variable[]>(
    () =>
      statDefinitions
        .filter((d) => d.code && (d.type === "int" || d.type === "float"))
        .map((d) => ({ code: d.code!, name: d.name ?? d.code! })),
    [statDefinitions]
  );
  // The variables read: the primary and every other one shown.
  const codes = useMemo(
    () => variables.map((v) => v.code).filter((c) => c === sizeBy || shownMeasures.includes(c)),
    [variables, sizeBy, shownMeasures]
  );
  const unitsLabel = getUnitTypeLabel(unitType) ?? "Units";
  const sizeLabel =
    sizeBy === "units"
      ? `Number of ${unitsLabel.toLowerCase()}`
      : `Total ${(variables.find((v) => v.code === sizeBy)?.name ?? sizeBy).toLowerCase()}`;

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

  // The selection's own figures come from one level up: its row among its parent's children.
  const { data: read, error, isLoading } = useSWR(
    regions && validOn && !isLeaf ? ["reports-map:read", strategy, unitType, at, validOn, codes.join(",")] : null,
    () => readMeasures(strategy, unitType, at, validOn!, codes),
    { revalidateOnFocus: false, keepPreviousData: true }
  );
  const { data: parentRead } = useSWR(
    regions && validOn && at ? ["reports-map:read", strategy, unitType, parentOf(at), validOn, codes.join(",")] : null,
    () => readMeasures(strategy, unitType, parentOf(at), validOn!, codes),
    { revalidateOnFocus: false }
  );
  const selectedMeasures: RegionMeasures | null = useMemo(() => {
    // Figures only from a read of the variables now shown: a kept earlier read lacks a newly
    // ticked one, which would show as 0 rather than as not read yet.
    const hasCodes = (rows: RegionMeasures[] | undefined) =>
      !!rows && (rows.length === 0 || codes.every((c) => c in rows[0].totals));
    if (at) return hasCodes(parentRead?.rows) ? (parentRead?.rows.find((r) => r.path === at) ?? null) : null;
    if (!read || !hasCodes(read.rows)) return null;
    return read.rows.reduce<RegionMeasures>(
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
  }, [at, parentRead, read, codes]);

  // At the lowest level the region's own units, by its path prefix.
  const { data: leafUnits } = useSWR(
    validOn && isLeaf ? ["reports-map:units", unitType, at, validOn, sizeBy] : null,
    () => readRegionUnits(unitType, at, validOn!, sizeBy),
    { revalidateOnFocus: false }
  );

  // Every unit type's totals for the selection side by side (Erik's legend, PR #325).
  const { data: typeTotals } = useSWR(
    validOn ? ["reports-map:types", at, validOn, codes.join(",")] : null,
    () => readTypeTotals(at, validOn!, codes),
    { revalidateOnFocus: false, keepPreviousData: true }
  );

  const valueOf = useCallback(
    (r: RegionMeasures) => (sizeBy === "units" ? r.units : (r.totals[sizeBy]?.sum ?? 0)),
    [sizeBy]
  );
  const ranked = useMemo(
    () => (isLeaf ? [] : [...(read?.rows ?? [])].sort((a, b) => valueOf(b) - valueOf(a))),
    [read, valueOf, isLeaf]
  );
  const features = useMemo<GeoJSON.FeatureCollection<GeoJSON.Point>>(() => {
    const placed = isLeaf ? (byPath.get(at) ? [{ path: at, units: 0, totals: {} }] : []) : ranked;
    return {
      type: "FeatureCollection",
      features: placed.flatMap((r) => {
        const g = byPath.get(r.path);
        if (g?.latitude == null || g.longitude == null) return [];
        return [
          {
            type: "Feature" as const,
            geometry: { type: "Point" as const, coordinates: [Number(g.longitude), Number(g.latitude)] },
            properties: {
              path: r.path,
              name: g.name,
              total: isLeaf ? 1 : valueOf(r),
              // The label's figures: the sizing measure, or with labelAll every ticked one.
              figures: isLeaf
                ? ""
                : labelAll
                  ? [
                      `${whole(r.units)} ${unitsLabel.toLowerCase()}`,
                      ...codes.map((c) => `${compactNumber.format(r.totals[c]?.sum ?? 0)} ${(variables.find((v) => v.code === c)?.name ?? c).toLowerCase()}`),
                    ].join("\n")
                  : whole(valueOf(r)),
            },
          },
        ];
      }),
    };
  }, [ranked, byPath, valueOf, isLeaf, at, labelAll, codes, variables, unitsLabel]);

  const go = useCallback((path: string) => {
    setPicked(null);
    setAt(path);
  }, []);

  // Frames every circle of the level. While zoom drives the level, the frame keeps the zoom inside
  // the level's band, so the next zoom the user makes is read from where the level starts.
  const featuresRef = useRef(features);
  const fitRef = useRef(() => {});
  const bandRef = useRef<[number, number] | null>(null);
  useGuardedEffect(
    () => {
      featuresRef.current = features;
      bandRef.current = zoomDrives ? zoomBand(depthOf(at)) : null;
      fitRef.current = () => {
        const map = mapRef.current;
        const b = featureBounds(featuresRef.current.features as never);
        if (!map || !b) return;
        const [w, s, e, n] = b;
        const camera =
          e - w < 0.01 && n - s < 0.01
            ? { center: [w, s] as [number, number], zoom: 9 }
            : map.cameraForBounds(b, { padding: 60, maxZoom: 10 });
        if (!camera) return;
        const band = bandRef.current;
        const zoom = band ? Math.min(Math.max(camera.zoom ?? 4, band[0]), band[1]) : camera.zoom;
        map.easeTo({ center: camera.center, zoom });
      };
    },
    [features, zoomDrives, at],
    "ReportsMap:fit"
  );

  const onReady = useCallback((map: MapLibreMap) => {
    mapRef.current = map;
    map.doubleClickZoom.disable();
    map.addSource("regions", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addSource("picked", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
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
      id: "picked-ring",
      type: "circle",
      source: "picked",
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
    setMapInstance(map);
    setMapReady(true);
  }, []);

  // A click on a circle picks the region and opens its spider; a double click goes in.
  const handlers = useRef({ pick: setPicked, go, hasChildren });
  useGuardedEffect(
    () => {
      handlers.current = { pick: setPicked, go, hasChildren };
    },
    [go, hasChildren],
    "ReportsMap:handlers"
  );
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      const onClick = (e: MapLayerMouseEvent) => {
        const f = map.queryRenderedFeatures(e.point, { layers: ["region-circles"] })[0];
        handlers.current.pick((f?.properties?.path as string | undefined) ?? null);
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

  // Zoom drives the level when switched on: past a band's edge the map goes into the region
  // nearest the view's centre, and back out when zoomed below the selection's band. A step made
  // by zooming keeps the view where the user put it (no frame).
  const steppedByZoom = useRef(false);
  const zoomRef = useRef({ zoomDrives, at, regions, byPath, hasChildren, go });
  useGuardedEffect(
    () => {
      zoomRef.current = { zoomDrives, at, regions, byPath, hasChildren, go };
    },
    [zoomDrives, at, regions, byPath, hasChildren, go],
    "ReportsMap:zoomRef"
  );
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      // Only the user's own zooms (wheel, pinch, the + and - buttons) carry an originalEvent; the
      // map's framing does not, so it never changes the level by itself.
      const onZoomEnd = (e: { originalEvent?: unknown }) => {
        const z = zoomRef.current;
        if (!z.zoomDrives || !e.originalEvent || !z.regions) return;
        const level = levelForZoom(map.getZoom());
        const depth = depthOf(z.at);
        if (level < depth) {
          steppedByZoom.current = true;
          z.go(z.at.split(".").slice(0, Math.max(level, 0)).join("."));
        } else if (level > depth && z.hasChildren.has(z.at)) {
          const centre = map.getCenter();
          const children = z.regions.filter(
            (r) => parentOf(r.path) === z.at && r.latitude != null && r.longitude != null
          );
          const nearest = children.reduce<MapRegion | null>((best, r) => {
            const d = (Number(r.latitude) - centre.lat) ** 2 + (Number(r.longitude) - centre.lng) ** 2;
            const bd = best ? (Number(best.latitude) - centre.lat) ** 2 + (Number(best.longitude) - centre.lng) ** 2 : Infinity;
            return d < bd ? r : best;
          }, null);
          if (nearest) {
            steppedByZoom.current = true;
            z.go(nearest.path);
          }
        }
      };
      map.on("zoomend", onZoomEnd);
      return () => {
        map.off("zoomend", onZoomEnd);
      };
    },
    [mapReady],
    "ReportsMap:zoomDrives"
  );

  const framed = useRef<string | null>(null);
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(features);
      (map.getSource("picked") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: features.features.filter((f) => f.properties?.path === picked),
      });
      map.setPaintProperty("region-circles", "circle-color", cssColour(`--color-${unitType}-500`));
      const max = Math.max(1, ...features.features.map((f) => Number(f.properties?.total ?? 0)));
      map.setPaintProperty("region-circles", "circle-radius", ["interpolate", ["linear"], ["sqrt", ["max", 0, ["get", "total"]]], 0, 4, Math.sqrt(max), 28]);
      map.setLayoutProperty("region-labels", "text-radial-offset", ["interpolate", ["linear"], ["sqrt", ["max", 0, ["get", "total"]]], 0, 8 / 13, Math.sqrt(max), 32 / 13]);
      map.setLayoutProperty("region-labels", "visibility", isLeaf ? "none" : "visible");
      if (features.features.length > 0 && framed.current !== at) {
        framed.current = at;
        if (steppedByZoom.current) steppedByZoom.current = false;
        else fitRef.current();
      }
    },
    [features, mapReady, unitType, at, picked, isLeaf],
    "ReportsMap:draw"
  );

  const pickedRow = ranked.find((r) => r.path === picked) ?? null;
  const pickedRegion = picked ? byPath.get(picked) : null;
  const unitsShown = shownMeasures.includes("units") || sizeBy === "units";
  const spiderMeasures = useMemo<SpiderMeasure[]>(() => {
    if (!pickedRow) return [];
    return [
      ...(unitsShown
        ? [{ key: "units", label: unitsLabel, value: pickedRow.units, colour: cssColour(`--color-${unitType}-500`) }]
        : []),
      ...variables
        .filter((v) => codes.includes(v.code))
        .map((v, i) => {
          const t = pickedRow.totals[v.code] ?? { sum: 0, count: 0 };
          return {
            key: v.code,
            label: v.name,
            value: t.sum,
            detail: t.count > 0 ? `mean ${mean(t.sum / t.count)}, ${whole(t.count)} of ${whole(pickedRow.units)} report it` : "no unit reports it",
            colour: VARIABLE_COLOURS[i % VARIABLE_COLOURS.length],
          };
        }),
    ];
  }, [pickedRow, variables, codes, unitsLabel, unitType, unitsShown]);

  const trail = ["", ...(at ? at.split(".").map((_, i, a) => a.slice(0, i + 1).join(".")) : [])];
  const nameOf = (p: string) => (p ? (byPath.get(p)?.name ?? p) : (countryName ?? "Country"));
  // The units behind a figure in Search: the place, the unit type, and sorted by the variable that
  // sizes the map, largest first, so the list opens on the units that make the total.
  const searchHref = (path: string) => {
    const q = new URLSearchParams();
    if (path) q.set(REGION, path);
    q.set(UNIT_TYPE, unitType);
    if (sizeBy !== "units") q.set("order", `${sizeBy}.desc.nullslast`);
    return `/search?${q}`;
  };
  // Leaves this map for Search's list of those units: the box-with-arrow-out icon (owner
  // 2026-11-27 20:32: a list icon is for this same view's own list, as on the search map).
  const listLink = (path: string, label: string) => (
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
          measures={[
            { key: "units", label: unitsLabel },
            ...variables.map((v) => ({ key: v.code, label: v.name })),
          ]}
          selected={shownMeasures}
          primary={sizeBy}
          onSelected={setShownMeasures}
          onPrimary={setSizeBy}
        />
        <label className="flex items-center gap-1" title="Prototype: zooming in goes into the region at the centre, zooming out goes up">
          <input type="checkbox" checked={zoomDrives} onChange={(e) => setZoomDrives(e.target.checked)} />
          Zoom changes the level
        </label>
      </div>
      {/* Ideas to try (Erik's PR #325 among them), each on its own switch while we explore. */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-gray-600" data-reports-map-try="">
        <span className="font-medium uppercase tracking-wide text-gray-500">Try</span>
        <span className="flex items-center gap-1" role="radiogroup" aria-label="Where a picked region's figures show">
          Picked region&rsquo;s figures:
          {(
            [
              ["map", "round it on the map"],
              ["side", "in the side panel"],
            ] as const
          ).map(([value, label]) => (
            <label key={value} className="flex items-center gap-1">
              <input
                type="radio"
                name="compare-in"
                checked={compareIn === value}
                onChange={() => {
                  setCompareIn(value);
                  // Shows the way at once on the largest region, when no eye is on (owner
                  // 2026-11-27 21:14: switching showed no difference with nothing shown).
                  if (!picked && ranked[0]) setPicked(ranked[0].path);
                }}
              />
              {label}
            </label>
          ))}
        </span>
        <label className="flex items-center gap-1">
          <input type="checkbox" checked={labelAll} onChange={(e) => setLabelAll(e.target.checked)} />
          Every ticked figure on the map labels
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" checked={typeSideBySide} onChange={(e) => setTypeSideBySide(e.target.checked)} />
          All unit types side by side
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" checked={unitCards} onChange={(e) => setUnitCards(e.target.checked)} />
          Unit cards at the lowest level
        </label>
      </div>
      {error && <p className="text-sm text-red-600" data-reports-map-error="">{String(error.message ?? error)}</p>}
      <div className="flex h-[70vh] min-h-0 rounded border">
        <div className="relative min-w-0 flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
          {mapInstance && compareIn === "map" && pickedRow && pickedRegion?.latitude != null && pickedRegion.longitude != null && (
            <VariableSpider
              map={mapInstance}
              coordinates={[Number(pickedRegion.longitude), Number(pickedRegion.latitude)]}
              name={pickedRegion.name}
              measures={spiderMeasures}
              onClose={() => setPicked(null)}
            />
          )}
        </div>
        <aside className="flex w-80 shrink-0 flex-col border-l text-sm" data-reports-map-side="">
          <div className="min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
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
            <section className="relative rounded border-2 border-gray-900 bg-gray-50 p-3" data-reports-map-selection="">
              {at && (
                <button
                  type="button"
                  className="absolute right-1.5 top-1.5 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                  title={`Back to ${nameOf(parentOf(at))}`}
                  aria-label={`Back to ${nameOf(parentOf(at))}`}
                  onClick={() => go(parentOf(at))}
                >
                  <X className="h-4 w-4" />
                </button>
              )}
              <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                {at ? "Selected region" : "Selected country"}
              </p>
              <h2 className="mr-6 flex items-center gap-1 font-medium">
                <span className="flex-1">
                  {nameOf(at)}
                  {at && <span className="ml-1.5 text-xs font-normal text-gray-500">{byPath.get(at)?.code ?? at}</span>}
                </span>
                {listLink(at, `the ${unitsLabel.toLowerCase()} of ${nameOf(at)}`)}
              </h2>
              {selectedMeasures ? (
                <dl className="mt-2 space-y-1" data-reports-map-selected-measures="">
                  {unitsShown && (
                    <div className="flex justify-between gap-2">
                      <dt>Number of {unitsLabel.toLowerCase()}</dt>
                      <dd className="tabular-nums">{whole(selectedMeasures.units)}</dd>
                    </div>
                  )}
                  {variables
                    .filter((v) => codes.includes(v.code))
                    .map((v) => {
                      const t = selectedMeasures.totals[v.code] ?? { sum: 0, count: 0 };
                      return (
                        <div key={v.code}>
                          <div className="flex justify-between gap-2">
                            <dt>Total {v.name.toLowerCase()}</dt>
                            <dd className="tabular-nums">{whole(t.sum)}</dd>
                          </div>
                          <p className="text-xs text-gray-500">
                            {t.count > 0
                              ? `mean ${mean(t.sum / t.count)} over the ${whole(t.count)} of ${whole(selectedMeasures.units)} that report it`
                              : "no unit reports it"}
                          </p>
                        </div>
                      );
                    })}
                </dl>
              ) : (
                <p className="mt-2 text-xs text-gray-500">{isLoading ? "Reading…" : ""}</p>
              )}
              {typeSideBySide && typeTotals && (
                // Each type's own total; they are never added together (establishments are parts of
                // legal units, legal units of enterprises).
                <table className="mt-3 w-full border-t pt-2 text-xs" data-reports-map-type-totals="">
                  <thead>
                    <tr className="text-gray-500">
                      <th className="pt-2 text-left font-normal" />
                      <th className="pt-2 text-right font-normal">Units</th>
                      {variables
                        .filter((v) => codes.includes(v.code))
                        .map((v) => (
                          <th key={v.code} className="pt-2 text-right font-normal">{v.name}</th>
                        ))}
                    </tr>
                  </thead>
                  <tbody>
                    {(["enterprise", "legal_unit", "establishment"] as UnitType[]).map((t) => {
                      const row = typeTotals.find((x) => x.unit_type === t);
                      return (
                        <tr key={t} className={t === unitType ? "font-semibold" : ""}>
                          <td className="py-0.5" style={{ color: cssColour(`--color-${t}-700`) }}>{getUnitTypeLabel(t)}</td>
                          <td className="text-right tabular-nums">{row ? compactNumber.format(row.units) : "–"}</td>
                          {variables
                            .filter((v) => codes.includes(v.code))
                            .map((v) => (
                              <td key={v.code} className="text-right tabular-nums">
                                {row ? compactNumber.format(row.totals[v.code]?.sum ?? 0) : "–"}
                              </td>
                            ))}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </section>
            {compareIn === "side" && pickedRow && selectedMeasures && (
              // The region the eye shows, beside the selection it is part of: each shown measure,
              // and how much of the selection's figure it holds.
              <section className="relative rounded border-2 border-dashed border-gray-400 p-3" data-reports-map-picked="">
                <button
                  type="button"
                  className="absolute right-1.5 top-1.5 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                  title="Hide"
                  aria-label="Hide"
                  onClick={() => setPicked(null)}
                >
                  <X className="h-4 w-4" />
                </button>
                <p className="flex items-center gap-1 text-xs font-medium uppercase tracking-wide text-gray-500">
                  <Eye className="h-3.5 w-3.5" aria-hidden /> Shown, part of {nameOf(at)}
                </p>
                <h2 className="mr-6 font-medium">{nameOf(pickedRow.path)}</h2>
                <dl className="mt-2 space-y-1">
                  {[
                    ...(unitsShown
                      ? [{ key: "units", label: `Number of ${unitsLabel.toLowerCase()}`, value: pickedRow.units, whole: selectedMeasures.units }]
                      : []),
                    ...variables
                      .filter((v) => codes.includes(v.code))
                      .map((v) => ({
                        key: v.code,
                        label: `Total ${v.name.toLowerCase()}`,
                        value: pickedRow.totals[v.code]?.sum ?? 0,
                        whole: selectedMeasures.totals[v.code]?.sum ?? 0,
                      })),
                  ].map((m) => {
                    const share = m.whole > 0 ? (100 * m.value) / m.whole : 0;
                    return (
                      <div key={m.key}>
                        <div className="flex justify-between gap-2">
                          <dt>{m.label}</dt>
                          <dd className="tabular-nums">
                            {whole(m.value)}{" "}
                            <span className="text-gray-500" title={`${share.toFixed(1)}% of ${nameOf(at)}'s ${m.label.toLowerCase()}`}>
                              ({share.toFixed(1)}% of {nameOf(at)})
                            </span>
                          </dd>
                        </div>
                        <div className="mt-0.5 h-1.5 rounded bg-gray-200" aria-hidden>
                          <div className="h-1.5 rounded bg-gray-700" style={{ width: `${Math.min(100, share)}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </dl>
              </section>
            )}
            {!isLeaf && ranked.length > 0 && (
              <section data-reports-map-children="">
                <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  {ranked.length} {at ? "subregions" : "regions"} by {sizeLabel.toLowerCase()}
                </h2>
                <ul className="mt-1 space-y-0.5">
                  {ranked.map((r) => (
                    <li
                      key={r.path}
                      className={`flex items-center gap-1 rounded ${r.path === picked ? "bg-gray-100" : "hover:bg-gray-100"}`}
                      data-child-row={r.path}
                    >
                      {/* As on the search map and the Regions map (owner 2026-11-27 21:02): a row
                          click goes into the region, so it becomes the Selected one above; the eye
                          shows a region's figures round its circle without going in. */}
                      <button
                        type="button"
                        className="flex min-w-0 flex-1 items-center justify-between gap-2 rounded px-1.5 py-1 text-left"
                        onClick={() => go(r.path)}
                        title={`Go into ${nameOf(r.path)}`}
                        data-child-enter={r.path}
                      >
                        <span className="truncate">{nameOf(r.path)}</span>
                        <span className="tabular-nums">{whole(valueOf(r))}</span>
                      </button>
                      <button
                        type="button"
                        className={`rounded p-1 hover:bg-gray-200 hover:text-gray-900 ${r.path === picked ? "text-gray-900" : "text-gray-400"}`}
                        title={r.path === picked ? `Hide ${nameOf(r.path)}'s figures` : `Show ${nameOf(r.path)}'s figures without going in`}
                        aria-pressed={r.path === picked}
                        onClick={() => setPicked(r.path === picked ? null : r.path)}
                      >
                        <Eye className="h-4 w-4" />
                      </button>
                      {listLink(r.path, `the ${unitsLabel.toLowerCase()} of ${nameOf(r.path)}`)}
                    </li>
                  ))}
                </ul>
              </section>
            )}
            {isLeaf && (
              <section data-reports-map-units="">
                <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  {sizeBy === "units" ? `The first ${unitsLabel.toLowerCase()} by name` : `Largest ${unitsLabel.toLowerCase()} by ${sizeLabel.toLowerCase()}`}
                </h2>
                <ul className="mt-1 space-y-0.5">
                  {(leafUnits ?? []).map((u) => {
                    const v = sizeBy === "units" ? null : u.stats_summary?.[sizeBy];
                    if (unitCards)
                      // Erik's popup as a card (PR #325): a header in the unit type's colour, where it
                      // is, its activity, and every variable it reports.
                      return (
                        <li key={`${u.unit_type}:${u.unit_id}`} className="overflow-hidden rounded border" data-reports-map-unit-card="">
                          <p className="truncate px-2 py-1 font-medium text-white" style={{ background: cssColour(`--color-${u.unit_type}-600`) }}>
                            {u.name}
                          </p>
                          <div className="space-y-0.5 px-2 py-1 text-xs">
                            <p className="text-gray-500">
                              {[nameOf(at), u.physical_postplace].filter(Boolean).join(", ")}
                              {u.primary_activity_category_code ? ` · activity ${u.primary_activity_category_code}` : ""}
                            </p>
                            {variables.map((vv) => {
                              const s = u.stats_summary?.[vv.code];
                              return s && typeof s === "object" && s.sum != null ? (
                                <p key={vv.code} className="flex justify-between">
                                  <span>{vv.name}</span>
                                  <span className="tabular-nums font-medium">{whole(Number(s.sum))}</span>
                                </p>
                              ) : null;
                            })}
                          </div>
                        </li>
                      );
                    return (
                      <li key={`${u.unit_type}:${u.unit_id}`} className="flex justify-between gap-2 px-1.5 py-0.5">
                        <span className="truncate">{u.name}</span>
                        {v && typeof v === "object" && <span className="tabular-nums">{whole(Number(v.sum ?? 0))}</span>}
                      </li>
                    );
                  })}
                </ul>
                <p className="mt-1 flex items-center gap-1 text-xs text-gray-600">
                  {listLink(at, `all the ${unitsLabel.toLowerCase()} of ${nameOf(at)}`)} All of them in Search
                </p>
              </section>
            )}
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
