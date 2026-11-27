"use client";

import { useCallback, useMemo, useRef, useState, type ReactNode } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Check, SquareArrowOutUpRight, X } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import type {
  GeoJSONSource,
  Map as MapLibreMap,
  MapLayerMouseEvent,
} from "maplibre-gl";
import { restClientAtom } from "@/atoms/rest-client";
import { useTimeFrame } from "@/atoms/app-derived";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UnitMap, cssColour } from "@/components/map/unit-map";
import { UnitTypeLegend } from "@/components/map/unit-type-legend";
import { BASEMAP_FONT, BASEMAP_FONT_BOLD } from "@/components/map/basemap";
import { ViewControl } from "@/components/map/view-control";
import { RegionSpiders } from "./region-spiders";
import { ChildList, type ChildRow } from "./child-list";
import {
  MAP_UNIT_TYPES,
  UNIT_TYPE_SWATCH,
  childCounts,
  countryCounts,
  countsAll,
  countsUnder,
  zeroCounts,
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
 * Where the search's map gets its counts (5nq78t): the units the search selects, by region.
 */
export interface RegionsMapSource {
  /** The SWR key part that changes when the counted units change (the search's filter). */
  key: string;
  /** False while what the counting needs is still loading; the map waits rather than count wrong. */
  ready?: boolean;
  /** One row per unit type, region path and country, for the units this map counts in the frame. */
  fetchRows: (validOn: string) => Promise<RegionCountRow[]>;
  /**
   * Keeps the counted rows a page's own filters allow, applied in the browser over one count (the
   * search's Country and Physical Location filters), so changing them does not count again.
   */
  rowFilter?: (row: RegionCountRow) => boolean;
}

/**
 * The search's map is a drill-down (owner 2026-11-23, z2qt08). One selection decides everything:
 * the world, the installation's own country (where the page opens), a foreign country, or a
 * region. The map shows the selection's children, one circle each, sized by its units, and the
 * panel lists the same children (owner 2026-11-24, as on a unit's Map page). A click on a circle
 * or a row picks that child: its row opens with its units per type, and its circle is ringed.
 * The selection is the search's place filter, so List shows its units. A double click on a circle, or
 * the row's chevron, goes in; the breadcrumb, the
 * panel's X (one level up) and the fit button act on the selection.
 * Zooming and panning only move the view; they do not change what is shown.
 *
 * Counts come from statistical_unit_facet, the pre-aggregated counts the reports' drilldown
 * reads: one row per unit type, region path and country in the time frame (1,793 rows, 0.18 s
 * on Norway, tmp/z2qt08-map-fetch2.sql), summed here per selection.
 */
/**
 * The selection and unit types when a page drives the map instead of the map's own URL (5nq78t: the
 * search's map, whose place and unit-type filters are the selection). The map reads them as given and
 * hands every change back; it keeps nothing of its own.
 */
export interface RegionsMapControl {
  selection: MapSelection;
  unitTypes: MapUnitType[];
  /** Go to a place: the page writes it into its own state (the search's place filters). */
  onSelect: (next: MapSelection) => void;
  onUnitTypes: (types: MapUnitType[]) => void;
  /** Countries the page narrows the world to (the search's Country filter), framed together. */
  countryIds?: number[] | null;
  /**
   * Turns one of the panel's parts on, in place of any other, or off when it is the one in effect
   * (owner 2026-11-27): units abroad (drawn per country), with no location, or in the country
   * without a region. The page writes the filters the toolbar has for each, so List shows them.
   */
  onFilter?: (part: "abroad" | "no-location" | "without-region") => void;
  /** The part in effect, read from the search's filters wherever they were set: its row is on. */
  activePart?: "abroad" | "no-location" | "without-region" | null;
  /**
   * The List view with a part the map cannot draw turned on (owner 2026-11-27: not on the map, so
   * in the list): units with no location, and units in the country without a region.
   */
  listHrefFor?: (part: "no-location" | "without-region") => string;
  /** The units the missing_region quality check lists under the search's filters: its row's count. */
  withoutRegionCount?: number;
}

export function RegionsMap({
  basePath,
  source,
  header,
  summary,
  control,
}: {
  /** The page's own path, which the selection and unit types extend (?at=, ?types=). */
  basePath: string;
  source: RegionsMapSource;
  /** The page header; it gets the region trail to place. */
  header: (breadcrumb: ReactNode) => ReactNode;
  /** What the counted units are, shown above the selection. */
  summary?: ReactNode;
  /** Set when a page drives the selection and unit types (the search's map). */
  control?: RegionsMapControl;
}) {
  const client = useAtomValue(restClientAtom);
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  // The selection and the unit types live in the URL (?at=50&types=legal_unit,establishment), so Back,
  // a reload or a shared link land where the map was. Each step in or out is a history
  // entry; a unit-type change replaces the current one. A page that drives the map (control) holds
  // them in its own state instead.
  const router = useRouter();
  const searchParams = useSearchParams();
  const requested = control
    ? control.selection
    : parseSelection(searchParams?.get("at") ?? null);
  const unitTypes = control
    ? control.unitTypes
    : parseUnitTypes(searchParams?.get("types") ?? null);
  const controlRef = useRef(control);
  // The map's handlers read the driving page's latest state through this, set after each render.
  useGuardedEffect(
    () => {
      controlRef.current = control;
    },
    [control],
    "RegionsMap:control"
  );
  // The map once its style has loaded: the type legs render over it.
  const [readyMap, setReadyMap] = useState<MapLibreMap | null>(null);
  const mapReady = readyMap !== null;
  const mapRef = useRef<MapLibreMap | null>(null);
  const featuresRef = useRef<
    GeoJSON.Feature<GeoJSON.Point, { total: number }>[]
  >([]);
  // The child picked by a click on its circle or row, with the selection it was picked in: a new
  // selection (going in, Back, the trail) leaves it behind, so it shows only where it was picked.
  const [pickedChild, setPickedChild] = useState<{
    at: MapSelection;
    path: string;
  } | null>(null);

  // The map's own handlers (click, fit) run outside React's render, so they read the
  // current selection and unit types at the moment they run: from the URL, or from the driving page.
  const current = useCallback(() => {
    const c = controlRef.current;
    if (c) return { at: c.selection, types: c.unitTypes };
    const params = new URLSearchParams(window.location.search);
    return {
      at: parseSelection(params.get("at")),
      types: parseUnitTypes(params.get("types")),
    };
  }, []);
  const mapUrl = useCallback(
    (at: MapSelection, types: readonly MapUnitType[]) => {
      const params = new URLSearchParams(window.location.search);
      params.delete("at");
      params.delete("types");
      if (at !== "") params.set("at", at === null ? "world" : at);
      if (types.join(",") !== DEFAULT_UNIT_TYPE)
        params.set("types", types.join(","));
      const query = params.toString();
      return query ? `${basePath}?${query}` : basePath;
    },
    [basePath]
  );
  const select = useCallback(
    (next: MapSelection) => {
      const { at, types } = current();
      if (next === at) return;
      const c = controlRef.current;
      if (c) c.onSelect(next);
      else router.push(mapUrl(next, types), { scroll: false });
    },
    [router, mapUrl, current]
  );
  const setUnitTypes = useCallback(
    (types: MapUnitType[]) => {
      const c = controlRef.current;
      if (c) c.onUnitTypes(types);
      else router.replace(mapUrl(current().at, types), { scroll: false });
    },
    [router, mapUrl, current]
  );

  // Circle sizes follow the largest circle in view: the area grows with the count, the
  // largest in view 28 px in radius.
  const scaleToView = useCallback((map: MapLibreMap) => {
    const view = map.getBounds();
    const top = Math.max(
      maxTotal(
        featuresRef.current.filter((f) =>
          view.contains(f.geometry.coordinates as [number, number])
        )
      ),
      1
    );
    map.setPaintProperty("region-circles", "circle-radius", [
      "interpolate",
      ["linear"],
      ["sqrt", ["get", "total"]],
      0,
      4,
      Math.sqrt(top),
      28,
    ]);
    // The picked circle's ring sits just outside it, at the same scale.
    map.setPaintProperty("picked-region-ring", "circle-radius", [
      "interpolate",
      ["linear"],
      ["sqrt", ["get", "total"]],
      0,
      8,
      Math.sqrt(top),
      32,
    ]);
    // Each label stands just outside its circle: the offset is in ems of the 13 px text, the
    // circle's radius plus a few pixels.
    map.setLayoutProperty("region-labels", "text-radial-offset", [
      "interpolate",
      ["linear"],
      ["sqrt", ["get", "total"]],
      0,
      (4 + 4) / 13,
      Math.sqrt(top),
      (28 + 4) / 13,
    ]);
    // A label is left out where it would stand on a larger place's circle (owner 2026-11-27:
    // Sweden's label stood on Norway's circle and read as the big one). The place keeps its
    // circle, its row in the list, and its label once zoomed in so the two stand apart.
    const crowded = crowdedLabels(map, featuresRef.current, Math.sqrt(top));
    map.setFilter(
      "region-labels",
      crowded.length > 0
        ? ["!", ["in", ["get", "path"], ["literal", crowded]]]
        : null
    );
  }, []);

  // Picks one child of the selection, from a click on its circle, one of its type legs or its row
  // (null: none). Its circle is ringed on the map; a row picked in the list also brings its
  // circle into view.
  const pickChild = useCallback(
    (path: string | null, from: "map" | "list" = "map") => {
      setPickedChild(path === null ? null : { at: current().at, path });
      const map = mapRef.current;
      const f = featuresRef.current.find(
        (x) =>
          (x.properties as unknown as RegionFeatureProperties).path === path
      );
      (map?.getSource("picked-region") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: f ? [f] : [],
      });
      if (
        map &&
        f &&
        from === "list" &&
        !map.getBounds().contains(f.geometry.coordinates as [number, number])
      ) {
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
    // The world frames its countries; narrowed to a few (the search's Country filter), it frames
    // just those, zoomed out until all are in view.
    const narrowed =
      at === null && (controlRef.current?.countryIds?.length ?? 0) > 0;
    const bounds = featureBounds(
      at === "" ? framingFeatures(features) : features
    );
    if (!bounds) return;
    const [west, south, east, north] = bounds;
    if (east - west < 0.01 && north - south < 0.01) {
      // A foreign country is its one circle, at its centre.
      map.easeTo({
        center: [west, south],
        zoom:
          at === null ? (narrowed ? 4 : 2) : selectionDepth(at) === 0 ? 4 : 9,
      });
      return;
    }
    map.fitBounds(bounds, {
      padding: 60,
      maxZoom: at === null ? (narrowed ? 6 : 4) : 11,
    });
  }, [current]);

  const { data: home } = useSWR(
    client ? ["regions-map:home"] : null,
    async () => {
      const { data, error } = await client!
        .from("settings")
        .select("country(id,name)")
        .limit(1)
        .single();
      if (error) throw error;
      return data.country as { id: number; name: string } | null;
    }
  );
  const homeId = home?.id ?? null;

  const { data: regions } = useSWR(
    client ? ["regions-map:regions"] : null,
    async () => {
      const { data, error } = await client!
        .from("region")
        .select("id,path,name,center_latitude,center_longitude,center_altitude")
        .order("path");
      if (error) throw error;
      return (data ?? []) as MapRegion[];
    }
  );
  const { data: countries } = useSWR(
    client ? ["regions-map:countries"] : null,
    async () => {
      const { data, error } = await client!
        .from("country")
        .select("id,iso_2,name,latitude,longitude");
      if (error) throw error;
      return new Map((data ?? []).map((c) => [c.id, c]));
    }
  );
  const countryByCode = useMemo(
    () => new Map([...(countries?.values() ?? [])].map((c) => [c.iso_2, c])),
    [countries]
  );
  // A region path or country code the tables do not have (an old or mistyped link) shows the
  // installation's own country, as does its own code.
  const requestedCode = selectedCountryCode(requested);
  const selection: MapSelection =
    requestedCode !== null
      ? countries &&
        (!countryByCode.has(requestedCode) ||
          countryByCode.get(requestedCode)?.id === home?.id)
        ? ""
        : requested
      : requested && regions && !regions.some((r) => r.path === requested)
        ? ""
        : requested;
  const selectedCountry =
    countryByCode.get(selectedCountryCode(selection) ?? "") ?? null;

  const {
    data: countedRows,
    error: countError,
    isLoading: counting,
  } = useSWR(
    client && validOn && source.ready !== false
      ? ["regions-map:counts", source.key, validOn]
      : null,
    () => source.fetchRows(validOn!)
  );
  const rowFilter = source.rowFilter;
  const rows = useMemo(
    () =>
      countedRows && rowFilter ? countedRows.filter(rowFilter) : countedRows,
    [countedRows, rowFilter]
  );

  // The panel's summary counts (in the country, abroad, no location, without a region) come from the
  // count before the place filters, so they stay as they are while one of them narrows the search
  // and the active one reads as a choice among them (owner 2026-11-27: counts dropping to 0 when
  // another was picked made it unclear what was in effect).
  const world = useMemo(
    () => worldCounts(countedRows ?? [], homeId, unitTypes),
    [countedRows, homeId, unitTypes]
  );
  const perCountry = useMemo(() => countryCounts(rows ?? []), [rows]);

  const regionName = useMemo(
    () => new Map((regions ?? []).map((r) => [r.path, r.name])),
    [regions]
  );
  const nameOf = useCallback(
    (s: MapSelection) => {
      if (s === null) return "World";
      if (s === "") return home?.name ?? "Country";
      const code = selectedCountryCode(s);
      return code !== null
        ? (countryByCode.get(code)?.name ?? code)
        : (regionName.get(s) ?? s);
    },
    [home, regionName, countryByCode]
  );

  // What the map draws for the selection: the children of a domestic selection; at the world
  // every country with units at its centre (country.latitude, longitude), the installation's
  // own one among them; a foreign country, which has no regions here, as its one circle. The
  // driving page's Country filter keeps only its countries.
  const countryIds = control?.countryIds ?? null;
  const { features, withoutCentre } = useMemo(() => {
    if (!rows || !regions)
      return {
        features: { type: "FeatureCollection" as const, features: [] },
        withoutCentre: [],
      };
    if (selection === null || selectedCountry) {
      const placed: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>[] =
        [];
      const unplaced: { path: string; name: string; total: number }[] = [];
      for (const [countryId, counts] of perCountry) {
        if (selectedCountry && countryId !== selectedCountry.id) continue;
        if (countryIds && !countryIds.includes(countryId)) continue;
        const total = selectedTotal(counts, unitTypes);
        if (total === 0) continue;
        const c = countries?.get(countryId);
        const name = c?.name ?? String(countryId);
        // The installation's own country is selected by "", a foreign one by its code.
        const path =
          countryId === homeId ? "" : `country:${c?.iso_2 ?? countryId}`;
        if (c?.latitude == null || c.longitude == null) {
          unplaced.push({ path, name, total });
          continue;
        }
        placed.push({
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [Number(c.longitude), Number(c.latitude)],
          },
          properties: { path, name, total, ...counts },
        });
      }
      return {
        features: { type: "FeatureCollection" as const, features: placed },
        withoutCentre: unplaced,
      };
    }
    const { features: f, withoutCentre: w } = regionFeatures(
      regions,
      childCounts(rows, selection, homeId),
      unitTypes
    );
    return { features: f, withoutCentre: w };
  }, [
    rows,
    regions,
    selection,
    selectedCountry,
    homeId,
    unitTypes,
    perCountry,
    countries,
    countryIds,
  ]);

  const selectedCounts = useMemo(() => {
    if (!rows || selection === null) return null;
    if (selectedCountry)
      return perCountry.get(selectedCountry.id) ?? zeroCounts();
    return countsUnder(rows, selection, homeId);
  }, [rows, selection, selectedCountry, perCountry, homeId]);
  const worldTypeCounts = useMemo(
    () => (rows ? countsAll(rows) : null),
    [rows]
  );

  // The circles take the colour of the one picked unit type, grey when types are mixed.
  const circleColour =
    unitTypes.length === 1
      ? `--color-${unitTypes[0]}-500`
      : "--color-informal-500";

  const onReady = useCallback(
    (map: MapLibreMap) => {
      mapRef.current = map;
      map.addSource("regions", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
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
      map.addSource("picked-region", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
      map.addLayer({
        id: "picked-region-ring",
        type: "circle",
        source: "picked-region",
        paint: {
          "circle-color": "rgba(0,0,0,0)",
          "circle-radius": [
            "interpolate",
            ["linear"],
            ["sqrt", ["get", "total"]],
            0,
            8,
            1000,
            32,
          ],
          "circle-stroke-color": "#111827",
          "circle-stroke-width": 3,
        },
      });
      map.addLayer({
        id: "region-labels",
        type: "symbol",
        source: "regions",
        // The label stands beside its circle, not on it, where the circle's fill and outline made
        // the text hard to read (owner 2026-11-24): below by default, else to the left, whichever is
        // free. The offset clears the circle as scaleToView sizes it; the name is bold and the
        // count plain, so the two lines read apart.
        layout: {
          "text-field": [
            "format",
            ["get", "name"],
            { "text-font": ["literal", BASEMAP_FONT_BOLD] },
            "\n",
            {},
            ["number-format", ["get", "total"], { locale: "en" }],
            {},
          ],
          "text-font": BASEMAP_FONT,
          "text-size": 13,
          // Below the circle, else to its left: the right of a circle is where its type pills stand.
          "text-variable-anchor": ["top", "right"],
          "text-radial-offset": 1.2,
          "text-justify": "auto",
          "text-allow-overlap": false,
          // Where two labels would collide, the place with more units keeps its name (owner
          // 2026-11-27: at World, Sweden's label stood on Norway's circle and Norway's was dropped,
          // so Sweden read as the big one). MapLibre places lower sort keys first.
          "symbol-sort-key": ["-", 0, ["get", "total"]],
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2.5,
          "text-halo-blur": 0.5,
        },
      });
      map.addControl(
        new ViewControl([
          {
            title: "Fit the selection in view",
            icon: "⤢",
            onClick: () => fitSelection(),
          },
        ]),
        "top-left"
      );
      map.on("moveend", () => scaleToView(map));
      map.on(
        "mouseenter",
        "region-circles",
        () => (map.getCanvas().style.cursor = "pointer")
      );
      map.on(
        "mouseleave",
        "region-circles",
        () => (map.getCanvas().style.cursor = "")
      );
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
        const feature = map.queryRenderedFeatures(e.point, {
          layers: ["region-circles"],
        })[0] as unknown as
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
  const framedSelection = useRef<string | undefined>(undefined);
  const picked =
    pickedChild && pickedChild.at === selection ? pickedChild.path : null;
  useGuardedEffect(
    () => {
      const map = mapRef.current;
      if (!map || !mapReady) return;
      (map.getSource("regions") as GeoJSONSource | undefined)?.setData(
        features
      );
      featuresRef.current = features.features;
      map.setPaintProperty(
        "region-circles",
        "circle-color",
        cssColour(circleColour)
      );
      scaleToView(map);
      // The ring follows the picked child's circle; at another selection there is none.
      const ringed = picked
        ? features.features.filter((f) => f.properties.path === picked)
        : [];
      (map.getSource("picked-region") as GeoJSONSource | undefined)?.setData({
        type: "FeatureCollection",
        features: ringed,
      });
      // A new selection, or a new set of countries at the world, is framed afresh.
      const framingKey = `${selection ?? "world"}|${countryIds?.join(",") ?? ""}`;
      if (
        features.features.length > 0 &&
        framedSelection.current !== framingKey
      ) {
        framedSelection.current = framingKey;
        fitSelection();
      }
    },
    [features, mapReady, circleColour, selection, picked, countryIds],
    "RegionsMapPage:setData"
  );

  const depth = selectionDepth(selection);
  // A region with no regions below it (a municipality) shows itself as its one circle.
  const isLeaf =
    depth > 0 &&
    features.features.length === 1 &&
    features.features[0].properties.path === selection;
  const childNoun =
    selection === null ? "countries" : depth === 0 ? "regions" : "subregions";
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);
  // The panel's list: the children the map draws. A region with regions below it can be entered;
  // a foreign country has none here, but going in shows it alone with its counts.
  const parentPaths = useMemo(
    () =>
      new Set(
        (regions ?? []).map((r) => r.path.split(".").slice(0, -1).join("."))
      ),
    [regions]
  );
  const childRows: ChildRow[] = isLeaf
    ? []
    : features.features.map((f) => {
        const p = f.properties;
        const country = p.path === "" || p.path.startsWith("country:");
        return {
          path: p.path,
          name: p.name,
          code: country ? null : p.path,
          counts: {
            enterprise: p.enterprise,
            legal_unit: p.legal_unit,
            establishment: p.establishment,
            power_group: p.power_group,
          },
          canEnter: country || parentPaths.has(p.path),
        };
      });

  // The trail: in the header on the Regions map; on the search's map, whose filter toolbar stands
  // between header and map, right above the selected region in the side panel, so the place and its
  // way up read together (owner 2026-11-26, 5nq78t).
  const trailNav = (
    <nav
      aria-label="Region trail"
      className="flex flex-wrap items-center gap-1 text-sm"
      data-regions-map-trail=""
    >
      {selectionTrail(selection).map((s, i, trail) => (
        <span key={s ?? "world"} className="flex items-center gap-1">
          {i > 0 && <span className="text-gray-400">›</span>}
          {i === trail.length - 1 ? (
            <span className="font-medium" aria-current="location">
              {nameOf(s)}
            </span>
          ) : (
            <button
              type="button"
              className="underline-offset-2 hover:underline"
              onClick={() => select(s)}
            >
              {nameOf(s)}
            </button>
          )}
        </span>
      ))}
      {/* Clears the whole place at once, back to the World (owner 2026-11-27: the panel's X steps
          up one level; this one drops the place filter). */}
      {selection !== null && (
        <button
          type="button"
          className="ml-1 rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-900"
          title="Clear the place: show the World"
          aria-label="Clear the place"
          onClick={() => select(null)}
          data-regions-map-trail-clear=""
        >
          <X className="h-3.5 w-3.5" />
        </button>
      )}
    </nav>
  );

  return (
    <main
      className="flex w-full flex-col"
      style={{ height: "calc(100vh - 56px)" }}
      data-regions-map-page=""
    >
      {/* The search's map lays its header out as the search's list does (full width, the same
          padding), so the List/Map switch stands on the same spot in both views (owner 2026-11-26). */}
      <div
        className={
          control
            ? "w-full px-2 pt-8 md:pt-12 lg:px-8"
            : "mx-auto w-full max-w-5xl px-2 pt-8 md:pt-12"
        }
      >
        {header(control ? null : trailNav)}
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
            <p
              className="absolute left-1/2 top-4 -translate-x-1/2 rounded bg-red-50 px-3 py-2 text-sm text-red-700 shadow"
              role="alert"
            >
              {countError instanceof Error
                ? countError.message
                : String(countError)}
            </p>
          )}
        </div>
        <aside
          className="flex w-72 shrink-0 flex-col border-l text-sm"
          data-regions-map-side=""
        >
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
            {summary}
            {control && trailNav}
            {counting && (
              <p
                className="text-xs text-gray-500"
                role="status"
                data-regions-map-counting=""
              >
                Counting the units by region…
              </p>
            )}
            {/* The selection stays put at the top while the list below it scrolls (owner 2026-11-24). */}
            <section
              className="sticky top-0 z-10 rounded border-2 border-gray-900 bg-gray-50 p-3 shadow-[0_-16px_0_0_white]"
              data-regions-map-selection=""
            >
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
              {selection !== null && (
                <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                  {depth === 0 ? "Selected country" : "Selected region"}
                </p>
              )}
              {/* The selected place: the search's own place filter, so its units are the List view's
                (owner 2026-11-27: no links out of the map to the list it switches with). The X
                beside it goes up a level. Editing a region's centre is the Regions map's. */}
              <h2
                className={`flex items-center font-medium ${selection !== null ? "mr-6" : ""}`}
                data-regions-map-selected-name=""
              >
                <span className="flex-1">
                  {nameOf(selection)}
                  {depth > 0 && (
                    <span className="ml-1.5 text-xs font-normal text-gray-500">
                      {selection}
                    </span>
                  )}
                </span>
              </h2>
              {!rows ? (
                // No counts yet, or counting failed (its message stands over the map): no numbers, rather
                // than zeros that read as an answer.
                <p
                  className="mt-2 text-xs text-gray-500"
                  data-regions-map-no-counts=""
                >
                  {countError ? "The counts could not be read." : "Counting…"}
                </p>
              ) : selectedCounts ? (
                // One list of unit types: tick to show a type on the map and in the list the button
                // opens; the count is the selection's (owner 2026-11-23: the types were listed twice,
                // as counts here and as a legend at the bottom).
                <div className="mt-3">
                  <UnitTypeLegend
                    selected={unitTypes}
                    onChange={setUnitTypes}
                    totals={selectedCounts}
                  />
                </div>
              ) : (
                <WorldSplit
                  world={world}
                  homeName={nameOf("")}
                  onHome={() => select("")}
                  onFilter={control?.onFilter}
                  activePart={control?.activePart}
                  listHrefFor={control?.listHrefFor}
                />
              )}
              {selection === null && (
                <div className="mt-3 border-t pt-3">
                  <UnitTypeLegend
                    selected={unitTypes}
                    onChange={setUnitTypes}
                    totals={worldTypeCounts ?? undefined}
                  />
                </div>
              )}
              <p
                className="mt-2 text-xs text-gray-500"
                data-regions-map-level=""
              >
                {!rows
                  ? null
                  : selectedCountry
                    ? `This registry has no regions of ${selectedCountry.name}. X or the trail above goes back up.`
                    : isLeaf
                      ? "The lowest level: no regions below this one. X or the trail above goes back up."
                      : features.features.length === 0
                        ? control?.activePart === "no-location" ||
                          control?.activePart === "without-region"
                          ? "These units have no place on the map: they are listed in List."
                          : "No units of the picked types here."
                        : null}
              </p>
            </section>
            {childRows.length > 0 && (
              <ChildList
                heading={`${features.features.length.toLocaleString()} ${childNoun}`}
                rows={childRows}
                unitTypes={unitTypes}
                picked={picked}
                onPick={(path) => pickChild(path, "list")}
                onEnter={select}
              />
            )}
            {selection !== null &&
              !selectedCountry &&
              ((selection === "" && world.domesticWithoutRegion > 0) ||
                withoutCentre.length > 0) && (
                <section className="space-y-2" data-regions-not-on-map="">
                  <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    Not on the map
                  </h2>
                  {selection === "" && world.domesticWithoutRegion > 0 && (
                    <CountRow
                      label={`Units in ${nameOf("")} without a region`}
                      value={
                        control
                          ? (control.withoutRegionCount ?? null)
                          : world.domesticWithoutRegion
                      }
                      href={control?.listHrefFor?.("without-region")}
                      onClick={
                        control?.onFilter &&
                        (() => control.onFilter!("without-region"))
                      }
                      active={control?.activePart === "without-region"}
                      title="Open them in the list (Quality: missing region); they are not on the map"
                      count="units-without-region"
                    />
                  )}
                  {withoutCentre.length > 0 && (
                    <div data-regions-without-coordinates="">
                      <p className="flex justify-between gap-2">
                        <span>Units in regions without coordinates</span>
                        <span className="tabular-nums text-gray-600">
                          {withoutCentre
                            .reduce((s, r) => s + r.total, 0)
                            .toLocaleString()}
                        </span>
                      </p>
                      <ul className="mt-0.5 space-y-0.5 pl-3 text-xs text-gray-600">
                        {withoutCentre.map((r) => (
                          <li
                            key={r.path}
                            className="flex items-center justify-between gap-2"
                          >
                            <span
                              className="truncate"
                              title={`${r.path} ${r.name}`}
                            >
                              {r.path} {r.name}
                            </span>
                            <span className="shrink-0 tabular-nums">
                              {r.total.toLocaleString()}
                            </span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </section>
              )}
            {selection === "" && (
              <p className="text-xs text-gray-500">
                Outside {nameOf("")}: {abroadTotal.toLocaleString()} units
                abroad and {world.noLocation.toLocaleString()} without a
                location.{" "}
                <button
                  type="button"
                  className="underline underline-offset-2"
                  onClick={() => select(null)}
                >
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

/**
 * The places whose label would stand on a larger place's circle at the current zoom: a label is
 * about 13 px high and the circles are sized as scaleToView sizes them (28 px for the largest in
 * view), so a smaller place whose centre lies within the larger circle's radius plus a label's
 * height is too close to name without covering it.
 */
function crowdedLabels(
  map: MapLibreMap,
  features: GeoJSON.Feature<GeoJSON.Point, { total: number }>[],
  sqrtTop: number
): string[] {
  const radius = (total: number) =>
    4 + (24 * Math.sqrt(total)) / Math.max(sqrtTop, 1);
  const placed = features.map((f) => ({
    path: (f.properties as unknown as RegionFeatureProperties).path,
    total: f.properties.total,
    at: map.project(f.geometry.coordinates as [number, number]),
  }));
  const crowded: string[] = [];
  for (const small of placed) {
    const covered = placed.some(
      (big) =>
        big.total > small.total &&
        Math.hypot(big.at.x - small.at.x, big.at.y - small.at.y) <
          radius(big.total) + 13
    );
    if (covered) crowded.push(small.path);
  }
  return crowded;
}

/** ?at= in the map's URL: absent is the country, "world" the world, "country:SE" a foreign country, else a region path. */
function parseSelection(at: string | null): MapSelection {
  if (at === null || at === "") return "";
  if (at === "world") return null;
  if (/^country:[A-Z]{2}$/.test(at)) return at;
  return /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(at) ? at : "";
}

/** ?types= in the map's URL: the picked unit types, enterprises when absent or unknown. */
function parseUnitTypes(types: string | null): MapUnitType[] {
  const picked = (types ?? "")
    .split(",")
    .filter((t): t is MapUnitType =>
      (MAP_UNIT_TYPES as readonly string[]).includes(t)
    );
  return picked.length > 0
    ? MAP_UNIT_TYPES.filter((t) => picked.includes(t))
    : [DEFAULT_UNIT_TYPE];
}

/**
 * A count in the panel (owner 2026-11-27): a full-width row, its count at the right. With a
 * handler it is one of the search's parts: ticked and shaded while its filter is in effect (set
 * here, in the list or in the toolbar), and a click turns it on in place of any other, or off. A
 * part the map cannot draw also has an href: turning it on opens those units in the List, its
 * arrow saying so; once on, a click turns it off here. Without either it is a plain count.
 */
function CountRow({
  label,
  value,
  onClick,
  href,
  active = false,
  title,
  count,
}: {
  label: ReactNode;
  value: number | null;
  onClick?: () => void;
  href?: string;
  active?: boolean;
  title?: string;
  count: string;
}) {
  const toList = href && !active;
  const inner = (
    <>
      <span className="flex flex-1 items-center gap-1.5">
        {onClick && (
          <Check
            className={`h-3.5 w-3.5 shrink-0 ${active ? "text-gray-900" : "invisible"}`}
            aria-hidden
          />
        )}
        {label}
      </span>
      <span className="tabular-nums text-gray-600">
        {value === null ? "…" : value.toLocaleString()}
      </span>
      {href && (
        <SquareArrowOutUpRight
          className={`h-3.5 w-3.5 shrink-0 self-center text-gray-500 ${toList ? "" : "invisible"}`}
          aria-hidden
        />
      )}
    </>
  );
  const row =
    "-mx-1.5 flex w-[calc(100%+0.75rem)] justify-between gap-2 rounded px-1.5 py-0.5 text-left";
  if (toList)
    return (
      <Link
        href={href}
        className={`${row} hover:bg-gray-100`}
        title={title}
        data-count={count}
      >
        {inner}
      </Link>
    );
  return onClick ? (
    <button
      type="button"
      className={`${row} ${active ? "bg-gray-200 font-medium" : "hover:bg-gray-100"}`}
      onClick={onClick}
      title={active ? "In effect: click to show all again" : title}
      aria-pressed={active}
      data-count={count}
    >
      {inner}
    </button>
  ) : (
    <p className="flex justify-between gap-2" data-count={count}>
      {inner}
    </p>
  );
}

/**
 * The world selection's summary: the units in the installation's own country, abroad, and without
 * a location. A click on one narrows the search to it, so the map and List follow (owner
 * 2026-11-27: the map and the list are one search). The countries themselves, each pickable and
 * enterable, are the list below it (ChildList), as the regions are at the other levels.
 */
function WorldSplit({
  world,
  homeName,
  onHome,
  onFilter,
  activePart,
  listHrefFor,
}: {
  world: ReturnType<typeof worldCounts>;
  homeName: string;
  onHome: () => void;
  onFilter?: RegionsMapControl["onFilter"];
  activePart?: RegionsMapControl["activePart"];
  listHrefFor?: RegionsMapControl["listHrefFor"];
}) {
  const abroadTotal = world.abroad.reduce((s, a) => s + a.count, 0);
  return (
    <div className="mt-2 space-y-0.5" data-regions-map-world="">
      <CountRow
        label={`In ${homeName}`}
        value={world.domestic}
        onClick={onHome}
        title={`Go to ${homeName}`}
        count="domestic"
      />
      <CountRow
        label={`Abroad, in ${world.abroad.length.toLocaleString()} countries`}
        value={abroadTotal}
        onClick={onFilter && (() => onFilter("abroad"))}
        active={activePart === "abroad"}
        title="Narrow the search to the units abroad (Domestic: No)"
        count="abroad"
      />
      <CountRow
        label="No location"
        value={world.noLocation}
        href={listHrefFor?.("no-location")}
        onClick={onFilter && (() => onFilter("no-location"))}
        active={activePart === "no-location"}
        title="Open the units with no location in the list (Physical Location: missing); they are not on the map"
        count="no-location"
      />
    </div>
  );
}
