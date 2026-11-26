"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { ChevronRight, Pencil, X } from "lucide-react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import type {
  GeoJSONSource,
  Map as MapLibreMap,
  MapLayerMouseEvent,
} from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { usePermission } from "@/atoms/auth";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap } from "@/components/map/unit-map";
import { BASEMAP_FONT } from "@/components/map/basemap";
import { ViewControl } from "@/components/map/view-control";
import { featureBounds } from "@/components/map/map-data";
import { RegionCentreDialog } from "../region-centre-dialog";
import { RegionsHeader } from "../regions-header";

/** A region as the map shows it: where it is, if it has a centre. */
interface MapRegion {
  id: number;
  path: string;
  code: string | null;
  name: string;
  center_latitude: number | null;
  center_longitude: number | null;
  center_altitude: number | null;
}

type DotProperties = { path: string; name: string };

/** The parent path of a region path: "46.4601" -> "46", "46" -> "" (the country). */
function parentOf(path: string): string {
  return path.split(".").slice(0, -1).join(".");
}

/** ?at= in the URL: a region path, or absent for the country's top level. */
function parseAt(at: string | null): string {
  return at && /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(at) ? at : "";
}

/**
 * The Regions map shows where the regions are, nothing else (owner 2026-11-26, z2qt08: the team
 * found it overlapped the search's map, which shows units by region). It opens on the country's
 * top regions; a region with regions below it can be entered, as the list's rows go down a level.
 * Every region with a centre is one dot of the same size, all of them framed, so a far-off region
 * (Svalbard) is in view; a region without a centre is listed under Not on the map, where an admin
 * places it. It reads only the region table, so it works before any unit is loaded.
 */
export function RegionsMap() {
  const client = useAtomValue(restClientAtom);
  const router = useRouter();
  const searchParams = useSearchParams();
  const requested = parseAt(searchParams?.get("at") ?? null);
  const { canAccessAdminTools } = usePermission();
  const [editing, setEditing] = useState<MapRegion | null>(null);
  const [picked, setPicked] = useState<string | null>(null);

  const { data: country } = useSWR(
    client ? ["regions-map:country"] : null,
    async () => {
      const { data, error } = await client!
        .from("settings")
        .select("country(name)")
        .limit(1)
        .single();
      if (error) throw error;
      return (data.country as { name: string } | null)?.name ?? null;
    }
  );
  const {
    data: regions,
    error: readError,
    mutate: reloadRegions,
  } = useSWR(client ? ["regions-map:regions"] : null, async () => {
    const { data, error } = await client!
      .from("region")
      .select(
        "id,path,code,name,center_latitude,center_longitude,center_altitude"
      )
      .order("path");
    if (error) throw error;
    return (data ?? []) as MapRegion[];
  });

  const byPath = useMemo(
    () => new Map((regions ?? []).map((r) => [r.path, r])),
    [regions]
  );
  const hasChildren = useMemo(
    () => new Set((regions ?? []).map((r) => parentOf(r.path))),
    [regions]
  );
  // A path the table does not have (an old or mistyped link) shows the top level.
  const at = requested && regions && !byPath.has(requested) ? "" : requested;
  const selected = at ? (byPath.get(at) ?? null) : null;
  // What the map shows: the selection's children, or a region with none below it as itself.
  const children = useMemo(
    () => (regions ?? []).filter((r) => parentOf(r.path) === at),
    [regions, at]
  );
  const shown = children.length === 0 && selected ? [selected] : children;
  const placed = shown.filter(
    (r) => r.center_latitude != null && r.center_longitude != null
  );
  const unplaced = shown.filter(
    (r) => r.center_latitude == null || r.center_longitude == null
  );
  const features = useMemo<
    GeoJSON.FeatureCollection<GeoJSON.Point, DotProperties>
  >(
    () => ({
      type: "FeatureCollection",
      features: placed.map((r) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [Number(r.center_longitude), Number(r.center_latitude)],
        },
        properties: { path: r.path, name: r.name },
      })),
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- placed is derived from shown each render
    [regions, at]
  );

  const go = useCallback(
    (path: string) => {
      setPicked(null);
      router.push(
        path ? `/regions/map?at=${encodeURIComponent(path)}` : "/regions/map",
        { scroll: false }
      );
    },
    [router]
  );

  const mapRef = useRef<MapLibreMap | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const featuresRef = useRef(features);
  // Frames every dot, the far-off ones too (the team asked where Svalbard was); one dot is
  // centred at a fixed zoom.
  const fitAll = useCallback(() => {
    const map = mapRef.current;
    const bounds = featureBounds(featuresRef.current.features);
    if (!map || !bounds) return;
    const [west, south, east, north] = bounds;
    if (east - west < 0.01 && north - south < 0.01) {
      map.easeTo({ center: [west, south], zoom: 9 });
      return;
    }
    map.fitBounds(bounds, { padding: 60, maxZoom: 11 });
  }, []);
  const pickRef = useRef<(path: string | null) => void>(() => {});
  const goRef = useRef(go);
  const hasChildrenRef = useRef(hasChildren);

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      map.addSource("regions", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
      map.addSource("picked", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
      map.addLayer({
        id: "region-dots",
        type: "circle",
        source: "regions",
        paint: {
          "circle-color": "#334155",
          "circle-radius": 6,
          "circle-stroke-color": "#ffffff",
          "circle-stroke-width": 1.5,
        },
      });
      map.addLayer({
        id: "picked-ring",
        type: "circle",
        source: "picked",
        paint: {
          "circle-color": "rgba(0,0,0,0)",
          "circle-radius": 10,
          "circle-stroke-color": "#111827",
          "circle-stroke-width": 3,
        },
      });
      map.addLayer({
        id: "region-names",
        type: "symbol",
        source: "regions",
        layout: {
          "text-field": ["get", "name"],
          "text-font": BASEMAP_FONT,
          "text-size": 13,
          "text-variable-anchor": ["top", "bottom", "left", "right"],
          "text-radial-offset": 0.8,
          "text-justify": "auto",
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      });
      map.addControl(
        new ViewControl([
          { title: "Show all the regions", icon: "⤢", onClick: () => fitAll() },
        ]),
        "top-left"
      );
      map.on(
        "mouseenter",
        "region-dots",
        () => (map.getCanvas().style.cursor = "pointer")
      );
      map.on(
        "mouseleave",
        "region-dots",
        () => (map.getCanvas().style.cursor = "")
      );
      // A click picks a region; a double click goes into one that has regions below it.
      map.on("click", (e) => {
        const f = map.queryRenderedFeatures(e.point, {
          layers: ["region-dots"],
        })[0];
        pickRef.current((f?.properties?.path as string | undefined) ?? null);
      });
      map.on("dblclick", "region-dots", (e: MapLayerMouseEvent) => {
        const path = e.features?.[0]?.properties?.path as string | undefined;
        if (path === undefined || !hasChildrenRef.current.has(path)) return;
        e.preventDefault();
        goRef.current(path);
      });
      setMapReady(true);
    },
    [fitAll]
  );

  const pick = useCallback((path: string | null) => {
    setPicked(path);
    const map = mapRef.current;
    const f = featuresRef.current.features.find(
      (x) => x.properties.path === path
    );
    (map?.getSource("picked") as GeoJSONSource | undefined)?.setData({
      type: "FeatureCollection",
      features: f ? [f] : [],
    });
    if (
      map &&
      f &&
      !map.getBounds().contains(f.geometry.coordinates as [number, number])
    ) {
      map.easeTo({ center: f.geometry.coordinates as [number, number] });
    }
  }, []);

  // The map's handlers read these when they run, so they are kept current after each render.
  useGuardedEffect(
    () => {
      pickRef.current = pick;
      goRef.current = go;
      hasChildrenRef.current = hasChildren;
    },
    [pick, go, hasChildren],
    "RegionsMap:handlers"
  );

  // New dots: drawn, and a new level framed whole. A saved centre redraws without moving the view.
  const framedAt = useRef<string | null>(null);
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady || !regions) return;
      featuresRef.current = features;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(
        features
      );
      const ringed = features.features.filter(
        (f) => f.properties.path === picked
      );
      (map.getSource("picked") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: ringed,
      });
      if (framedAt.current !== at && features.features.length > 0) {
        framedAt.current = at;
        fitAll();
      }
    },
    [features, mapReady, regions, at, picked, fitAll],
    "RegionsMap:draw"
  );

  const countryName = country ?? "Country";
  const trail = (
    <nav
      aria-label="Region trail"
      className="flex flex-wrap items-center gap-1 text-sm"
      data-regions-map-trail=""
    >
      {[
        "",
        ...(at
          ? at
              .split(".")
              .map((_, i, labels) => labels.slice(0, i + 1).join("."))
          : []),
      ].map((p, i, all) => (
        <span key={p || "country"} className="flex items-center gap-1">
          {i > 0 && <span className="text-gray-400">›</span>}
          {i === all.length - 1 ? (
            <span className="font-medium" aria-current="location">
              {p ? (byPath.get(p)?.name ?? p) : countryName}
            </span>
          ) : (
            <button
              type="button"
              className="underline-offset-2 hover:underline"
              onClick={() => go(p)}
            >
              {p ? (byPath.get(p)?.name ?? p) : countryName}
            </button>
          )}
        </span>
      ))}
    </nav>
  );

  const editButton = (r: MapRegion, label: string) =>
    canAccessAdminTools && (
      <button
        type="button"
        className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
        onClick={() => setEditing(r)}
        title={label}
        aria-label={`${label}: ${r.name}`}
        data-regions-map-edit-centre={r.path}
      >
        <Pencil className="h-3.5 w-3.5" />
      </button>
    );

  return (
    <main
      className="flex w-full flex-col"
      style={{ height: "calc(100vh - 56px)" }}
      data-regions-map-page=""
    >
      <div className="mx-auto w-full max-w-5xl px-2 pt-8 md:pt-12">
        <RegionsHeader view="map" breadcrumb={trail} />
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="relative min-w-0 flex-1">
          <UnitMap onReady={onReady} className="absolute inset-0" />
          {readError && (
            <p
              className="absolute left-1/2 top-4 -translate-x-1/2 rounded bg-red-50 px-3 py-2 text-sm text-red-700 shadow"
              role="alert"
            >
              The regions could not be read:{" "}
              {readError instanceof Error
                ? readError.message
                : String(readError)}
            </p>
          )}
        </div>
        <aside
          className="flex w-72 shrink-0 flex-col border-l text-sm"
          data-regions-map-side=""
        >
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
            {selected && (
              <section
                className="relative rounded border-2 border-gray-900 bg-gray-50 p-3"
                data-regions-map-selection=""
              >
                <button
                  type="button"
                  className="absolute right-1.5 top-1.5 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                  title="Up one level"
                  aria-label="Up one level"
                  onClick={() => go(parentOf(selected.path))}
                >
                  <X className="h-4 w-4" />
                </button>
                <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  Selected region
                </p>
                <h2 className="mr-6 flex items-center gap-1 font-medium">
                  <span className="flex-1">
                    {selected.name}
                    <span className="ml-1.5 text-xs font-normal text-gray-500">
                      {selected.code ?? selected.path}
                    </span>
                  </span>
                  {editButton(selected, "Edit the centre")}
                </h2>
                <p className="mt-1 text-xs tabular-nums text-gray-600">
                  {selected.center_latitude != null &&
                  selected.center_longitude != null
                    ? `${selected.center_latitude}, ${selected.center_longitude}${selected.center_altitude != null ? `, ${selected.center_altitude} m` : ""}`
                    : "No centre"}
                </p>
              </section>
            )}
            {regions && regions.length === 0 && (
              <p className="text-gray-600" data-regions-map-empty="">
                There are no regions yet.{" "}
                <Link
                  href="/getting-started/upload-regions"
                  className="underline underline-offset-2"
                >
                  Upload regions
                </Link>
              </p>
            )}
            {children.length > 0 && (
              <section data-regions-map-children="">
                <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  {children.length.toLocaleString()}{" "}
                  {at ? "subregions" : "regions"}
                </h2>
                <ul className="mt-1 space-y-0.5">
                  {children.map((r) => (
                    <li
                      key={r.path}
                      className={`flex items-center gap-1 rounded ${r.path === picked ? "bg-gray-100" : "hover:bg-gray-100"}`}
                      data-child-row={r.path}
                    >
                      <button
                        type="button"
                        className="min-w-0 flex-1 truncate rounded px-1.5 py-1 text-left"
                        onClick={() => pick(r.path === picked ? null : r.path)}
                      >
                        {r.name}
                        <span className="ml-1 text-xs text-gray-500">
                          {r.code ?? r.path}
                        </span>
                      </button>
                      {hasChildren.has(r.path) && (
                        <button
                          type="button"
                          className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                          title={`Go into ${r.name}`}
                          aria-label={`Go into ${r.name}`}
                          onClick={() => go(r.path)}
                          data-child-enter={r.path}
                        >
                          <ChevronRight className="h-4 w-4" />
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              </section>
            )}
            {unplaced.length > 0 && (
              <section data-regions-not-on-map="">
                <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  Not on the map: no centre
                </h2>
                <ul className="mt-1 space-y-0.5 text-gray-700">
                  {unplaced.map((r) => (
                    <li
                      key={r.path}
                      className="flex items-center justify-between gap-2 px-1.5"
                      data-region-without-centre={r.path}
                    >
                      <span className="truncate">
                        {r.name}
                        <span className="ml-1 text-xs text-gray-500">
                          {r.code ?? r.path}
                        </span>
                      </span>
                      {editButton(r, "Place on the map")}
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        </aside>
      </div>
      {editing && (
        <RegionCentreDialog
          region={editing}
          editing
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            // The dots are drawn from the centres, so the region moves at once.
            void reloadRegions();
          }}
        />
      )}
    </main>
  );
}
