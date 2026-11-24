"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { Maximize2, Minimize2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from "maplibre-gl";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "./unit-map";
import { BASEMAP_FONT } from "./basemap";
import { ViewControl } from "./view-control";
import { featureBounds, linksUnitPoints, type LinksHierarchy, type MapUnitType, type UnitPointProperties } from "./map-data";
import { UnitsSpider, type SpiderStack } from "./units-spider";

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
  // The map once its style has loaded: the spider renders over it.
  const [readyMap, setReadyMap] = useState<MapLibreMap | null>(null);
  const mapReady = readyMap !== null;
  // The stack a click opened as a spider, and which of its nodes is listed (null: all of it).
  const [spider, setSpider] = useState<SpiderStack | null>(null);
  const [spiderKey, setSpiderKey] = useState<string | null>(null);
  const closeSpider = useCallback(() => setSpider(null), [setSpider]);
  // Expand fills the window with the map; Escape or the button brings it back to the page.
  const [expanded, setExpanded] = useState(false);
  const mapRef = useRef<MapLibreMap | null>(null);
  const shownRef = useRef<GeoJSON.Feature<GeoJSON.Point, UnitPointProperties>[]>([]);
  // The units at exactly the page's unit's place, listed with it on a click.
  const alsoHereRef = useRef<UnitPointProperties[]>([]);

  const points = useMemo(
    () => (hierarchy?.enterprise ? linksUnitPoints(hierarchy as unknown as LinksHierarchy, { unitType, id: Number(unitId) }) : null),
    [hierarchy, unitType, unitId]
  );
  // Per unit type, how many are at their address and how many at their region's centre; the
  // legend shows both, each with the marker the map draws (owner 2026-11-23).
  const counts = useMemo(() => {
    const c: Record<"legal_unit" | "establishment", { point: number; region: number }> = {
      legal_unit: { point: 0, region: 0 },
      establishment: { point: 0, region: 0 },
    };
    for (const f of points?.features.features ?? []) {
      if (f.properties.unit_type === "legal_unit" || f.properties.unit_type === "establishment") c[f.properties.unit_type][f.properties.placed] += 1;
    }
    return c;
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
      // Units close on screen are one circle with their count, which splits as the map zooms
      // in (owner 2026-11-23: the country view showed overlapping circles); units at exactly the
      // same place (a region's centre) stay one circle at any zoom. The circle keeps how many
      // of each unit type it holds and whether the page's unit is among them.
      map.addSource("units", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        cluster: true,
        clusterRadius: 40,
        clusterMaxZoom: 22,
        clusterProperties: {
          has_current: ["any", ["get", "current"]],
          legal_units: ["+", ["case", ["==", ["get", "unit_type"], "legal_unit"], 1, 0]],
          establishments: ["+", ["case", ["==", ["get", "unit_type"], "establishment"], 1, 0]],
          // How many are at their address: all of them, none or some decides the group's marker.
          at_address: ["+", ["case", ["==", ["get", "placed"], "point"], 1, 0]],
        },
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
      // A group of units at one place, in its unit type's colour (grey when both types are
      // there); its count is always drawn, over the unit names.
      const groupColour = [
        "case",
        ["==", ["get", "legal_units"], 0],
        cssColour("--color-establishment-500"),
        ["==", ["get", "establishments"], 0],
        cssColour("--color-legal_unit-500"),
        cssColour("--color-informal-500"),
      ] as unknown as string;
      // A group follows the single units' marker rule (owner 2026-11-24): solid with a white count
      // when all its units are at their address, a ring when all are somewhere in their region,
      // and a ring with a solid core when it holds some of each.
      const groupRadius = ["interpolate", ["linear"], ["sqrt", ["get", "point_count"]], 1, 10, 20, 30] as unknown as number;
      const allAtAddress = ["==", ["get", "at_address"], ["get", "point_count"]];
      const someAtAddress = ["all", [">", ["get", "at_address"], 0], ["<", ["get", "at_address"], ["get", "point_count"]]];
      map.addLayer({
        id: "unit-groups",
        type: "circle",
        source: "units",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": ["case", allAtAddress, groupColour, "#ffffff"] as unknown as string,
          "circle-stroke-color": ["case", ["get", "has_current"], "#111827", allAtAddress, "#ffffff", groupColour] as unknown as string,
          "circle-stroke-width": 3,
          "circle-radius": groupRadius,
        },
      });
      // The core of a group with units both at their address and in their region: a pale disc in
      // the group's colour inside its ring, so its count stays readable on it.
      map.addLayer({
        id: "unit-group-cores",
        type: "circle",
        source: "units",
        filter: ["all", ["has", "point_count"], someAtAddress] as unknown as boolean,
        paint: {
          "circle-color": groupColour,
          "circle-opacity": 0.35,
          "circle-radius": ["*", 0.75, groupRadius] as unknown as number,
        },
      });
      map.addLayer({
        id: "unit-group-counts",
        type: "symbol",
        source: "units",
        filter: ["has", "point_count"],
        layout: {
          "text-field": ["get", "point_count_abbreviated"],
          "text-font": BASEMAP_FONT,
          "text-size": 12,
          "text-allow-overlap": true,
          "text-ignore-placement": true,
        },
        paint: { "text-color": ["case", allAtAddress, "#ffffff", "#111827"] as unknown as string },
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
      // The page's own unit is never merged into a circle: it is drawn by itself, ringed and
      // named, on top of the others (owner 2026-11-23: on a shop's page the shop was hidden in a
      // circle of 19).
      map.addSource("current-unit", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "current-unit-point",
        type: "circle",
        source: "current-unit",
        paint: {
          "circle-color": ["case", ["==", ["get", "placed"], "point"], colour, "#ffffff"],
          "circle-radius": 9,
          "circle-stroke-color": "#111827",
          "circle-stroke-width": 3,
        },
      });
      map.addLayer({
        id: "current-unit-label",
        type: "symbol",
        source: "current-unit",
        layout: {
          "text-field": ["get", "name"],
          "text-font": BASEMAP_FONT,
          "text-size": 12,
          "text-offset": [0, 1.2],
          "text-anchor": "top",
          "text-allow-overlap": true,
        },
        paint: { "text-color": "#111827", "text-halo-color": "#ffffff", "text-halo-width": 2 },
      });
      // The units at exactly this unit's place, as small dots in their own colour inside its
      // ring, spread round its centre when there are several (owner 2026-11-23). Drawn as icons,
      // since an icon's offset can differ per dot and a circle's cannot.
      const dot = (fill: string, stroke: string) => {
        const size = 20; // drawn at twice the size, shown at pixelRatio 2: 10 px
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = size;
        const ctx = canvas.getContext("2d")!;
        ctx.beginPath();
        ctx.arc(size / 2, size / 2, size / 2 - 2, 0, 2 * Math.PI);
        ctx.fillStyle = fill;
        ctx.fill();
        ctx.lineWidth = 3;
        ctx.strokeStyle = stroke;
        ctx.stroke();
        return ctx.getImageData(0, 0, size, size);
      };
      for (const t of ["legal_unit", "establishment"] as const) {
        const c = cssColour(`--color-${t}-500`);
        map.addImage(`also-${t}-point`, dot(c, "#ffffff"), { pixelRatio: 2 });
        map.addImage(`also-${t}-region`, dot("#ffffff", c), { pixelRatio: 2 });
      }
      map.addSource("current-unit-also", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "current-unit-also",
        type: "symbol",
        source: "current-unit-also",
        layout: {
          "icon-image": ["concat", "also-", ["get", "unit_type"], "-", ["get", "placed"]],
          "icon-offset": ["get", "offset"],
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
        },
      });
      for (const layer of ["unit-points", "unit-groups", "current-unit-point"]) {
        map.on("mouseenter", layer, () => (map.getCanvas().style.cursor = "pointer"));
        map.on("mouseleave", layer, () => (map.getCanvas().style.cursor = ""));
      }
      map.on("click", "current-unit-point", (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (f) setPicked([f.properties as UnitPointProperties, ...alsoHereRef.current]);
      });
      map.on("click", "unit-points", (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (f) setPicked([f.properties as UnitPointProperties]);
      });
      // A click on a circle lists its units. Units spread over several places zoom in until the
      // circle splits; units that all share one place (a region's centre) never split, so the
      // circle opens as a spider instead: one leg per unit type and placement, each with its
      // count in its type's colour (owner 2026-11-24).
      map.on("click", "unit-groups", async (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (!f) return;
        const source = map.getSource("units") as GeoJSONSource;
        const id = f.properties.cluster_id as number;
        const leaves = await source.getClusterLeaves(id, 10000, 0);
        const units = leaves.map((l) => l.properties as UnitPointProperties).sort((a, b) => Number(b.current) - Number(a.current) || a.name.localeCompare(b.name));
        setPicked(units);
        const places = new Set(leaves.map((l) => (l.geometry as GeoJSON.Point).coordinates.join(",")));
        if (places.size > 1) {
          setSpider(null);
          const zoom = await source.getClusterExpansionZoom(id);
          map.easeTo({ center: (f.geometry as GeoJSON.Point).coordinates as [number, number], zoom });
          return;
        }
        setSpiderKey(null);
        setSpider({ coordinates: (leaves[0].geometry as GeoJSON.Point).coordinates as [number, number], units });
      });
      // A click on the map away from every unit closes the spider.
      map.on("click", (e) => {
        const hit = map.queryRenderedFeatures(e.point, { layers: ["unit-groups", "unit-points", "current-unit-point"] });
        if (hit.length === 0) setSpider(null);
      });
      setReadyMap(map);
    },
    [fit, setPicked, setSpider, setSpiderKey, setReadyMap]
  );

  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      // Units at exactly the page's unit's place (the same region centre, the same address)
      // would hide under it; they go with it instead, counted as "+n" beside its ring and
      // listed with it on a click (owner 2026-11-23).
      const current = shown.features.find((f) => f.properties.current);
      const samePlace = (f: (typeof shown.features)[number]) =>
        !!current &&
        f.geometry.coordinates[0] === current.geometry.coordinates[0] &&
        f.geometry.coordinates[1] === current.geometry.coordinates[1];
      const withCurrent = shown.features.filter((f) => !f.properties.current && samePlace(f));
      (map.getSource("units") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: shown.features.filter((f) => !f.properties.current && !samePlace(f)),
      });
      (map.getSource("current-unit") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: current
          ? [{ ...current, properties: { ...current.properties } }]
          : [],
      });
      // One small dot per unit at this place; a single one sits in the ring's centre, several
      // are spread on a small circle so each shows.
      (map.getSource("current-unit-also") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: withCurrent.map((f, i) => {
          const angle = (2 * Math.PI * i) / withCurrent.length - Math.PI / 2;
          const r = withCurrent.length === 1 ? 0 : 4;
          return { ...f, properties: { ...f.properties, offset: [Math.round(r * Math.cos(angle)), Math.round(r * Math.sin(angle))] } };
        }),
      });
      alsoHereRef.current = withCurrent.map((f) => f.properties);
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

  // A new size (expand, back) is measured, and the units framed in it.
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      map.resize();
      fit();
      if (!expanded) return;
      const onKey = (e: KeyboardEvent) => e.key === "Escape" && setExpanded(false);
      window.addEventListener("keydown", onKey);
      return () => window.removeEventListener("keydown", onKey);
    },
    [expanded, mapReady, fit],
    "UnitsMap:expanded"
  );

  if (!points) return null;
  const unplaced = points.total - points.atPoint - points.atRegion;
  // A list from one circle is headed by its region when all its units share one.
  const regions = new Set((picked ?? []).map((u) => u.region_name ?? ""));
  const regionName = picked && picked.length > 1 && regions.size === 1 ? picked[0].region_name : undefined;
  return (
    <section
      className={expanded ? "fixed inset-0 z-50 flex flex-col gap-2 bg-white p-4" : "space-y-2"}
      data-units-map=""
      data-expanded={expanded ? "" : undefined}
    >
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-sm text-gray-600" data-units-map-placed="">
          {points.total.toLocaleString()} units of this enterprise: {points.atPoint.toLocaleString()} at their address,{" "}
          {points.atRegion.toLocaleString()} at their region&apos;s centre
          {unplaced > 0 ? `, ${unplaced.toLocaleString()} with no place` : ""}.
        </p>
        <Button type="button" variant="outline" size="sm" onClick={() => setExpanded((e) => !e)} data-units-map-expand="">
          {expanded ? <Minimize2 className="mr-1.5 h-4 w-4" /> : <Maximize2 className="mr-1.5 h-4 w-4" />}
          {expanded ? "Back to the page" : "Expand"}
        </Button>
      </div>
      <div
        className={`flex overflow-hidden rounded-md border ${expanded ? "min-h-0 flex-1" : ""}`}
        style={expanded ? undefined : { height: "min(70vh, 40rem)" }}
      >
        <div className="relative min-w-0 flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
          {spider && readyMap && (
            <UnitsSpider
              key={spider.coordinates.join(",")}
              map={readyMap}
              stack={spider}
              selectedKey={spiderKey}
              onPick={(key, units) => {
                setSpiderKey(key);
                setPicked(units);
              }}
              onClose={closeSpider}
            />
          )}
        </div>
        <aside className="flex w-64 shrink-0 flex-col border-l text-sm">
          <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-3" data-units-map-picked="">
            {picked ? (
              <>
                {picked.length > 1 && (
                  <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    {regionName ? `${picked.length} in ${regionName}` : `${picked.length} units`}
                  </p>
                )}
                <ul className="space-y-1">
                  {picked.map((u) => (
                    <li key={`${u.unit_type}:${u.id}`} className="flex items-start gap-2">
                      {/* The unit type's marker: a legal unit and its establishment often share a name. */}
                      <span
                        className={`mt-1 inline-block h-2.5 w-2.5 shrink-0 rounded-full ${
                          u.placed === "point"
                            ? u.unit_type === "legal_unit" ? "bg-legal_unit-500" : "bg-establishment-500"
                            : `border-2 bg-white ${u.unit_type === "legal_unit" ? "border-legal_unit-500" : "border-establishment-500"}`
                        }`}
                        title={u.unit_type === "legal_unit" ? "Legal unit" : "Establishment"}
                        aria-hidden
                      />
                      <span>
                        <Link className="underline underline-offset-2" href={u.href}>
                          {u.name}
                        </Link>
                        <span className="ml-1 text-xs text-gray-500">
                          {u.unit_type === "legal_unit" ? "legal unit" : "establishment"}
                          {u.current ? ", this unit" : ""}
                        </span>
                        {u.placed === "region" && picked.length === 1 && (
                          <span className="block text-xs text-gray-500">Somewhere in {u.region_name}</span>
                        )}
                      </span>
                    </li>
                  ))}
                </ul>
              </>
            ) : (
              <p className="text-xs text-gray-500">Click a dot or a circle for its units.</p>
            )}
          </div>
          <div className="border-t p-3">
            <UnitsLegend
              selected={unitTypes}
              onChange={(next) => {
                // The stacks are regrouped for the new types, so an open spider is closed.
                setSpider(null);
                setUnitTypes(next);
              }}
              counts={counts}
            />
          </div>
        </aside>
      </div>
    </section>
  );
}

const LEGEND_TYPES = [
  { unitType: "legal_unit", label: "Legal units" },
  { unitType: "establishment", label: "Establishments" },
] as const;

/** The marker colours per kind of group: one unit type in its colour, mixed types in grey (unit-groups' groupColour). */
const MARKER_SWATCH = {
  legal_unit: { fill: "bg-legal_unit-500", ring: "border-legal_unit-500", core: "bg-legal_unit-500/35" },
  establishment: { fill: "bg-establishment-500", ring: "border-establishment-500", core: "bg-establishment-500/35" },
  mixed: { fill: "bg-informal-500", ring: "border-informal-500", core: "bg-informal-500/35" },
} as const;

/**
 * The three markers the map draws, by where the units are (owner 2026-11-24): solid at the
 * unit's address, a ring somewhere in its region, and for a group with some of each a ring
 * with a pale core (unit-group-cores at 0.35).
 */
function PlacementMarker({ kind, placed }: { kind: keyof typeof MARKER_SWATCH; placed: "point" | "region" | "both" }) {
  const s = MARKER_SWATCH[kind];
  if (placed === "point") return <span className={`inline-block h-3.5 w-3.5 shrink-0 rounded-full ${s.fill}`} aria-hidden />;
  return (
    <span className={`relative inline-block h-3.5 w-3.5 shrink-0 rounded-full border-2 bg-white ${s.ring}`} aria-hidden>
      {placed === "both" && <span className={`absolute inset-[1.5px] rounded-full ${s.core}`} />}
    </span>
  );
}

/** One legend row: a marker, what it means, and how many units it stands for when that is one number. */
function PlacementRow({ kind, placed, label, count }: { kind: keyof typeof MARKER_SWATCH; placed: "point" | "region" | "both"; label: string; count?: number }) {
  return (
    <p className="flex items-center gap-2" data-legend-kind={kind} data-legend-placed={placed}>
      <PlacementMarker kind={kind} placed={placed} />
      <span className="flex-1">{label}</span>
      {count !== undefined && <span className="tabular-nums">{count.toLocaleString()}</span>}
    </p>
  );
}

/**
 * The Map page's legend (owner 2026-11-24): one grid. Each unit type, and the grey group of
 * mixed unit types, has the same three markers: at the address, somewhere in the region, and
 * a group with some of each. A unit type has a checkbox (at least one stays picked) and its
 * counts; one line says every circle is a group that expands on a click.
 */
function UnitsLegend({
  selected,
  onChange,
  counts,
}: {
  selected: readonly MapUnitType[];
  onChange: (next: MapUnitType[]) => void;
  counts: Record<"legal_unit" | "establishment", { point: number; region: number }>;
}) {
  const toggle = (t: MapUnitType) => {
    const next = selected.includes(t) ? selected.filter((s) => s !== t) : [...selected, t];
    if (next.length > 0) onChange(LEGEND_TYPES.map((l) => l.unitType).filter((u) => next.includes(u)));
  };
  return (
    <fieldset className="space-y-2 text-sm" data-units-legend="">
      <legend className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-500">Units</legend>
      {LEGEND_TYPES.map(({ unitType, label }) => (
        <div key={unitType}>
          <label className="flex cursor-pointer items-center gap-2">
            <input type="checkbox" checked={selected.includes(unitType)} onChange={() => toggle(unitType)} data-unit-type={unitType} />
            <span className="flex-1">{label}</span>
            <span className="tabular-nums text-gray-600">
              {(counts[unitType].point + counts[unitType].region).toLocaleString()}
            </span>
          </label>
          <div className="mt-0.5 space-y-0.5 pl-6 text-xs text-gray-600">
            <PlacementRow kind={unitType} placed="point" label="At its address" count={counts[unitType].point} />
            <PlacementRow kind={unitType} placed="region" label="Somewhere in its region" count={counts[unitType].region} />
            <PlacementRow kind={unitType} placed="both" label="Some of each" />
          </div>
        </div>
      ))}
      <div data-legend-mixed="">
        <p className="pl-6">Mixed unit types</p>
        <div className="mt-0.5 space-y-0.5 pl-6 text-xs text-gray-600">
          <PlacementRow kind="mixed" placed="point" label="At their address" />
          <PlacementRow kind="mixed" placed="region" label="Somewhere in their region" />
          <PlacementRow kind="mixed" placed="both" label="Some of each" />
        </div>
      </div>
      <p className="text-xs text-gray-500" data-legend-group="">
        A circle with a number is a group: click to expand it.
      </p>
    </fieldset>
  );
}
