"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useAtomValue, useSetAtom } from "jotai";
import useSWR from "swr";
import { List as ListIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { restClientAtom } from "@/atoms/rest-client";
import { externalIdentTypesAtom, statDefinitionsAtom } from "@/atoms/base-data";
import {
  fetchSearchPageDataAtom,
  searchFilterApiParams,
  searchPageDataAtom,
  searchPageDataReadyAtom,
} from "@/atoms/search";
import { useBaseData } from "@/atoms/base-data";
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { deriveStateFromUrl } from "@/app/search/derive-state-from-url";
import {
  facetParams,
  liveCountSelect,
  type RegionCountRow,
} from "@/components/map/map-data";
import {
  RegionsMap,
  type RegionsMapSource,
} from "@/app/regions/map/regions-map";
import { SearchRow } from "@/app/regions/map/open-in-search";

/** The map's own URL parameters; everything else in the URL is the search's. */
const MAP_PARAMS = ["at", "types"];

/**
 * The Reports map (5nq78t): the units a search selects, counted by region in the selected time
 * frame, as the Regions map draws every unit. Its URL is the search's own query string, plus the
 * map's ?at= and ?types=; the search page's Map button opens it, and its "View and download" rows
 * open /search with the same filter, narrowed to a place. With no filter it maps the whole register.
 *
 * Counts come from statistical_unit_facet when every filter is a facet column (0.1-0.6 s on
 * Norway), else from statistical_unit grouped by region with the list's own filter (seconds, as the
 * list's own scan): facetParams decides. Section 4a of doc/design/units-on-map.md has the design.
 */
export default function ReportsMapPage() {
  const client = useAtomValue(restClientAtom);
  const searchParams = useSearchParams();
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  const { allDataSources } = useAtomValue(searchPageDataAtom);
  const searchPageDataReady = useAtomValue(searchPageDataReadyAtom);
  const { loading: baseDataLoading } = useBaseData();
  // The filter's codes become ids through these: external identifier types and statistics (base
  // data) and data sources (the search's lookups). Counting before they arrive would count a
  // different filter.
  const lookupsReady = !baseDataLoading && searchPageDataReady;
  const fetchSearchPageData = useSetAtom(fetchSearchPageDataAtom);
  // A data-source filter names sources by code; the list of sources turns them into ids.
  useGuardedEffect(
    () => void fetchSearchPageData(),
    [fetchSearchPageData],
    "ReportsMapPage:lookups"
  );

  // The search's own part of the URL, as the search page reads it.
  const searchUrl = useMemo(() => {
    const p = new URLSearchParams(searchParams?.toString() ?? "");
    for (const k of MAP_PARAMS) p.delete(k);
    p.delete("page");
    p.delete("order");
    p.sort();
    return p;
  }, [searchParams]);
  const searchUrlString = searchUrl.toString();

  const { data: homeId } = useSWR(
    client ? ["reports-map:home"] : null,
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

  const source: RegionsMapSource = useMemo(() => {
    const { _initialQuery, _initialFilters } = deriveStateFromUrl(
      new URLSearchParams(searchUrlString),
      externalIdentTypes,
      statDefinitions
    );
    // The unit types are the map's own choice (its legend), so the search's are left out here and
    // the links to the search put the map's in.
    const filters = { ...(_initialFilters as Record<string, unknown>) };
    delete filters.unit_type;
    const filterOnly = (validOn: string | null) =>
      searchFilterApiParams({
        query: _initialQuery,
        filters,
        validOn,
        externalIdentTypes,
        statDefinitions,
        allDataSources,
      });
    const linkFilter = new URLSearchParams(searchUrlString);
    linkFilter.delete("unit_type");
    return {
      // The API filter itself, with the home country it may be rewritten with: it changes when the
      // lookups a filter needs (data sources by code) arrive, so a count made before them is not
      // reused after.
      key: `${filterOnly(null).toString()}|${homeId ?? ""}`,
      // Counting waits for the installation's country (domestic) and the lookups the filter reads.
      ready: homeId !== undefined && lookupsReady,
      searchFilter: linkFilter,
      fetchRows: async (validOn: string): Promise<RegionCountRow[]> => {
        const api = filterOnly(validOn);
        const facet = facetParams(api, homeId ?? null);
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
    };
  }, [
    client,
    searchUrlString,
    externalIdentTypes,
    statDefinitions,
    allDataSources,
    homeId,
    lookupsReady,
  ]);

  const listHref = `/search?${searchUrlString}`;
  const filtered = [...searchUrl.keys()].some((k) => k !== "unit_type");

  return (
    <RegionsMap
      basePath="/reports/map"
      source={source}
      header={(trail) => (
        <div
          className="relative mb-6 flex items-center justify-center lg:mb-12"
          data-reports-map-header=""
        >
          <div className="absolute left-0 max-w-[35%]">{trail}</div>
          <h1 className="text-center text-xl lg:text-2xl">Units on the map</h1>
          <Link
            href={listHref}
            className={`${buttonVariants({ variant: "outline", size: "sm" })} absolute right-0`}
            data-reports-map-list-link=""
          >
            <ListIcon className="mr-1.5 h-4 w-4" />
            List
          </Link>
        </div>
      )}
      summary={
        <section
          className="rounded border bg-white p-3"
          data-reports-map-filter=""
        >
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Units
          </p>
          <SearchRow
            href={listHref}
            title="View and download these units in the search"
            data-reports-map-search=""
          >
            <span className="flex-1">
              {filtered
                ? describeFilter(searchUrl)
                : "All units in the register"}
            </span>
          </SearchRow>
        </section>
      }
    />
  );
}

/** The filter with the count's own select in place of the list's. */
function withSelect(api: URLSearchParams, select: string): string {
  const p = new URLSearchParams(api);
  p.set("select", select);
  return p.toString();
}

/** The search's filters as one readable line ("search: bygg, activity: C"), from its URL. */
function describeFilter(url: URLSearchParams): string {
  const label: Record<string, string> = {
    search: "name",
    primary_activity_category_path: "activity",
    physical_region_path: "region",
    sector_path: "sector",
    legal_form_code: "legal form",
    status_code: "status",
    domestic: "domestic",
    physical_location: "location",
    physical_country: "country",
    unit_size_code: "size",
    data_source: "data source",
    quality: "quality",
    last_edit_by_user_id: "edited by",
  };
  return [...url.entries()]
    .filter(([k]) => k !== "unit_type")
    .map(([k, v]) => `${label[k] ?? k}: ${v}`)
    .join(", ");
}
