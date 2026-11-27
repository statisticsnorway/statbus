"use client";

import { useCallback, useMemo } from "react";
import { useSearchParams } from "next/navigation";
import { useAtomValue, useSetAtom } from "jotai";
import { searchUrlPushNextAtom } from "@/atoms/app";
import useSWR from "swr";
import { restClientAtom } from "@/atoms/rest-client";
import { useBaseData } from "@/atoms/base-data";
import {
  searchFilterApiParams,
  searchPageDataAtom,
  searchPageDataReadyAtom,
  useSearchFilters,
  useSearchQuery,
} from "@/atoms/search";
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { SearchResults } from "@/app/search/SearchResults";
import TableToolbar from "@/app/search/components/table-toolbar";
import { SearchViewHeader } from "@/app/search/components/search-view-header";
import {
  DOMESTIC,
  PHYSICAL_COUNTRY,
  PHYSICAL_LOCATION,
  QUALITY,
  REGION,
  UNIT_TYPE,
} from "@/app/search/filters/url-search-params";
import { qualityCheckParam } from "@/lib/quality-checks";
import {
  MAP_UNIT_TYPES,
  facetParams,
  liveCountSelect,
  resolveQualityForCount,
  selectedCountryCode,
  type MapSelection,
  type MapUnitType,
  type RegionCountRow,
} from "@/components/map/map-data";
import {
  RegionsMap,
  type RegionsMapControl,
  type RegionsMapSource,
} from "./regions-map";

/** The filters that say where units are: the map's selection, applied over one count. */
const PLACE_FILTERS = [
  REGION,
  PHYSICAL_COUNTRY,
  DOMESTIC,
  PHYSICAL_LOCATION,
  UNIT_TYPE,
];

const asList = (v: unknown): string[] =>
  Array.isArray(v)
    ? (v.filter((x) => x !== null && x !== "") as string[])
    : typeof v === "string" && v
      ? [v]
      : [];

/**
 * The search's map view (5nq78t, owner 2026-11-26): the same search as the list, the same filters
 * on top, one selection. Where the units are (region, country, domestic, location) is the map's
 * selection: going into a region sets the Region filter, the trail and X take it off again, and
 * the legend's ticks are the Unit Type filter, so List shows exactly what the map shows. The map
 * counts once, by region and country, for every other filter (statistical_unit_facet when the
 * facet has them, else statistical_unit grouped), and applies the place filters in the browser,
 * so drilling in and out is instant and asks the database nothing. Design: doc/design/units-on-map.md
 * section 4a.
 */
export default function SearchMapPageClient({
  initialUrlSearchParamsString,
}: {
  initialUrlSearchParamsString: string;
}) {
  return (
    <SearchResults
      allRegions={[]}
      allActivityCategories={[]}
      allStatuses={[]}
      allUnitSizes={[]}
      allDataSources={[]}
      allExternalIdentTypes={[]}
      allLegalForms={[]}
      allSectors={[]}
      initialUrlSearchParamsString={initialUrlSearchParamsString}
      view="map"
    >
      <SearchMap />
    </SearchResults>
  );
}

function SearchMap() {
  const client = useAtomValue(restClientAtom);
  const { filters, updateFilters } = useSearchFilters();
  const setPushNext = useSetAtom(searchUrlPushNextAtom);
  const searchParams = useSearchParams();
  const { query } = useSearchQuery();
  const {
    externalIdentTypes,
    statDefinitions,
    loading: baseDataLoading,
  } = useBaseData();
  const { allDataSources, allStatuses, allLegalForms, allCountries } =
    useAtomValue(searchPageDataAtom);
  const searchPageDataReady = useAtomValue(searchPageDataReadyAtom);
  const lookupsReady = !baseDataLoading && searchPageDataReady;
  // A quality check names its variable by code; the findings hold its id (resolveQualityForCount).
  const statIds = useMemo(
    () =>
      new Map(
        (statDefinitions ?? []).flatMap((d) =>
          d.code && d.id != null ? [[d.code, d.id] as const] : []
        )
      ),
    [statDefinitions]
  );

  const { data: homeId } = useSWR(
    client ? ["search-map:home"] : null,
    async () => {
      const { data, error } = await client!
        .from("settings")
        .select("country_id")
        .limit(1)
        .single();
      if (error) throw error;
      return (data.country_id as number | null) ?? null;
    }
  );

  // The place filters as the map's selection.
  const regionPath = asList(filters[REGION])[0] ?? null;
  const countryIds = asList(filters[PHYSICAL_COUNTRY]).map(Number);
  const domestic = asList(filters[DOMESTIC])[0] ?? null;
  const location = asList(filters[PHYSICAL_LOCATION])[0] ?? null;
  const pickedTypes = asList(filters[UNIT_TYPE]).filter((t): t is MapUnitType =>
    (MAP_UNIT_TYPES as readonly string[]).includes(t)
  );
  const unitTypes: MapUnitType[] =
    pickedTypes.length > 0
      ? MAP_UNIT_TYPES.filter((t) => pickedTypes.includes(t))
      : [...MAP_UNIT_TYPES];
  const isoOf = useMemo(
    () => new Map((allCountries ?? []).map((c) => [c.id, c.iso_2])),
    [allCountries]
  );
  const idOfIso = useMemo(
    () => new Map((allCountries ?? []).map((c) => [c.iso_2, c.id])),
    [allCountries]
  );

  const selection: MapSelection =
    regionPath && regionPath !== "null"
      ? regionPath
      : countryIds.length === 1 && countryIds[0] !== homeId
        ? `country:${isoOf.get(countryIds[0]) ?? ""}`
        : domestic === "true" ||
            regionPath === "null" ||
            (countryIds.length === 1 && countryIds[0] === homeId)
          ? ""
          : null;

  // The count: every filter but the place ones and the unit types, so the map counts once and the
  // place filters and legend apply over it.
  const counted = useMemo(() => {
    const rest = Object.fromEntries(
      Object.entries(filters).filter(([k]) => !PLACE_FILTERS.includes(k))
    );
    return rest;
  }, [filters]);
  const codeIds = useMemo(
    () => ({
      status: new Map((allStatuses ?? []).map((s) => [s.code, s.id])),
      legalForm: new Map(
        (allLegalForms ?? [])
          .filter((l) => l.code && l.id != null)
          .map((l) => [l.code as string, l.id as number])
      ),
    }),
    [allStatuses, allLegalForms]
  );
  const filterOnly = useCallback(
    (validOn: string | null) =>
      searchFilterApiParams({
        query,
        filters: counted,
        validOn,
        externalIdentTypes,
        statDefinitions,
        allDataSources,
      }),
    [query, counted, externalIdentTypes, statDefinitions, allDataSources]
  );

  // The place filters the selection cannot say on its own are kept over the one count, as the list
  // applies them: Physical Location (a country or none), Domestic No (abroad), several countries,
  // and Region none (units in the country without a region).
  const countryKey = countryIds.join(",");
  const placeKept =
    Boolean(location) ||
    domestic === "false" ||
    countryIds.length > 1 ||
    regionPath === "null";
  const rowFilter = useCallback(
    (row: RegionCountRow) => {
      const c = row.physical_country_id;
      const several = countryKey ? countryKey.split(",").map(Number) : [];
      if (location === "missing" && c != null) return false;
      if (location === "present" && c == null) return false;
      if (domestic === "false" && (c == null || c === homeId)) return false;
      if (several.length > 1 && (c == null || !several.includes(c)))
        return false;
      if (regionPath === "null" && row.physical_region_path != null)
        return false;
      return true;
    },
    [location, domestic, homeId, countryKey, regionPath]
  );

  const source: RegionsMapSource = useMemo(
    () => ({
      key: `${filterOnly(null).toString()}|${homeId ?? ""}|${codeIds.status.size}:${codeIds.legalForm.size}`,
      ready: homeId !== undefined && lookupsReady,
      rowFilter: placeKept ? rowFilter : undefined,
      fetchRows: async (validOn: string): Promise<RegionCountRow[]> => {
        const api = resolveQualityForCount(filterOnly(validOn), statIds);
        const facet = facetParams(api, homeId ?? null, codeIds);
        const base = client!.url.endsWith("/")
          ? client!.url
          : `${client!.url}/`;
        const url = facet
          ? new URL(
              `statistical_unit_facet?select=unit_type,physical_region_path,physical_country_id,count.sum()&${facet}`,
              base
            )
          : new URL(
              `statistical_unit?${withSelect(api, liveCountSelect(api))}`,
              base
            );
        const response = await fetchWithAuthRefresh(url.toString(), {
          headers: { Accept: "application/json" },
        });
        if (!response.ok)
          throw new Error(
            `Counting the units by region failed (${response.status}): ${await response.text()}`
          );
        const rows = (await response.json()) as {
          unit_type: RegionCountRow["unit_type"];
          physical_region_path: string | null;
          physical_country_id: number | null;
          sum?: number;
          count?: number;
        }[];
        // Only the grouped columns and the count: an embedded filter (a quality check) comes back as
        // its own field and is left out here.
        return rows.map((r) => ({
          unit_type: r.unit_type,
          physical_region_path: r.physical_region_path,
          physical_country_id: r.physical_country_id,
          count: Number(r.sum ?? r.count ?? 0),
        }));
      },
    }),
    [
      client,
      filterOnly,
      homeId,
      codeIds,
      lookupsReady,
      statIds,
      placeKept,
      rowFilter,
    ]
  );

  // Going to a place writes the search's place filters, as the toolbar would: the country's own
  // units are Domestic Yes, a foreign country is its Country, a region is its Region (regions are
  // the country's own). The other filters stay as they are.
  const onSelect = useCallback(
    (next: MapSelection) => {
      // Each step in or out is a history entry, so Back returns to the place before.
      setPushNext(true);
      const out: Record<string, unknown> = {
        ...filters,
        [REGION]: [],
        [PHYSICAL_COUNTRY]: [],
        [DOMESTIC]: [],
      };
      if (next === "") out[DOMESTIC] = ["true"];
      else if (next !== null) {
        const code = selectedCountryCode(next);
        if (code !== null)
          out[PHYSICAL_COUNTRY] = [String(idOfIso.get(code) ?? "")];
        else out[REGION] = [next];
      }
      updateFilters(out);
    },
    [filters, updateFilters, idOfIso, setPushNext]
  );
  const onUnitTypes = useCallback(
    (types: MapUnitType[]) =>
      updateFilters({
        ...filters,
        [UNIT_TYPE]: types.length === MAP_UNIT_TYPES.length ? [] : types,
      }),
    [filters, updateFilters]
  );
  // A count in the panel narrows the search to its part, with the filter the toolbar has for it, so
  // it shows in the bar and List lists the same units; a step of its own, so Back undoes it.
  const onFilter = useCallback(
    (part: "abroad" | "no-location" | "without-region") => {
      setPushNext(true);
      const out: Record<string, unknown> = {
        ...filters,
        [REGION]: [],
        [PHYSICAL_COUNTRY]: [],
        [DOMESTIC]: [],
      };
      if (part === "abroad") out[DOMESTIC] = ["false"];
      if (part === "no-location") out[PHYSICAL_LOCATION] = ["missing"];
      if (part === "without-region") {
        out[DOMESTIC] = ["true"];
        out[QUALITY] = [qualityCheckParam("missing_region", null)];
      }
      updateFilters(out);
    },
    [filters, updateFilters, setPushNext]
  );
  const control: RegionsMapControl = {
    selection,
    unitTypes,
    onSelect,
    onUnitTypes,
    onFilter,
    countryIds: selection === null && countryIds.length > 1 ? countryIds : null,
  };

  return (
    <RegionsMap
      basePath="/search/map"
      source={source}
      control={control}
      header={(trail) => (
        <div className="space-y-3">
          <SearchViewHeader view="map" breadcrumb={trail} />
          <TableToolbar />
        </div>
      )}
    />
  );
}

/** The filter with the count's own select in place of the list's. */
function withSelect(api: URLSearchParams, select: string): string {
  const p = new URLSearchParams(api);
  p.set("select", select);
  return p.toString();
}
