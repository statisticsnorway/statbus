"use client";

import { ReactNode, useMemo, useReducer } from "react";
import { useTimeContext } from "@/app/time-context";
import useSWR from "swr";
import { modifySearchStateReducer } from "@/app/search/search-filter-reducer";
import useDerivedUrlSearchParams from "@/app/search/use-derived-url-search-params";
import { useBaseData } from "@/app/BaseDataClient";
import { SearchContext, SearchContextState } from "@/app/search/search-context";
import { TableColumnsProvider } from "./table-columns";
import { SearchResult, SearchOrder, SearchPagination, SearchState, SearchAction } from "./search.d";
import type { Tables } from "@/lib/database.types";
import { toURLSearchParams, URLSearchParamsDict } from "@/lib/url-search-params-dict";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { getStatisticalUnits } from "./search-requests";
import {
  activityCategoryDeriveStateUpdateFromSearchParams,
  dataSourceDeriveStateUpdateFromSearchParams,
  externalIdentDeriveStateUpdateFromSearchParams,
  fullTextSearchDeriveStateUpdateFromSearchParams,
  invalidCodesDeriveStateUpdateFromSearchParams,
  legalFormDeriveStateUpdateFromSearchParams,
  regionDeriveStateUpdateFromSearchParams,
  sectorDeriveStateUpdateFromSearchParams,
  statisticalVariablesDeriveStateUpdateFromSearchParams,
  statusDeriveStateUpdateFromSearchParams,
  unitSizeDeriveStateUpdateFromSearchParams,
  unitTypeDeriveStateUpdateFromSearchParams,
} from "./filters/url-search-params";

const fetcher = async (derivedApiSearchParams: URLSearchParams) => {
  // Use getBrowserRestClient instead of createPostgRESTBrowserClient
  // This ensures we're using the singleton pattern correctly
  const client = await getBrowserRestClient();
  try {
    const response = await getStatisticalUnits(client, derivedApiSearchParams);
    return response
  } catch (error) {
    console.error("Failed to fetch data:", error);
    throw error;
  }
};

/**
 * Extract values from URLSearchParams and initialize search state.
 * This avoid a double fetch during loading, because the useEffect of all
 * the filters are triggered after the useEffect of SearchResults, so their
 * initial state changes must be incorporated here.
 */
function initializeSearchStateFromUrlSearchParams(
  modifySearchStateReducer: (
    state: SearchState,
    action: SearchAction
  ) => SearchState,
  emptySearchState: SearchState,
  initialUrlSearchParams: URLSearchParams,
  maybeDefaultExternalIdentType: Tables<"external_ident_type_ordered">,
  statDefinitions: Tables<"stat_definition_ordered">[],
  allDataSources: Tables<"data_source">[]
): SearchState {
  let actions = [
    fullTextSearchDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    unitTypeDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    invalidCodesDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    legalFormDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    regionDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    sectorDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    activityCategoryDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    statusDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    unitSizeDeriveStateUpdateFromSearchParams(initialUrlSearchParams),
    dataSourceDeriveStateUpdateFromSearchParams(
      initialUrlSearchParams,
      allDataSources
    ),
    externalIdentDeriveStateUpdateFromSearchParams(
      maybeDefaultExternalIdentType,
      initialUrlSearchParams
    ),
  ].concat(
    statisticalVariablesDeriveStateUpdateFromSearchParams(
      statDefinitions,
      initialUrlSearchParams
    )
  );
  let result = actions.reduce(modifySearchStateReducer, emptySearchState);
  result = { ...result, pagination: emptySearchState.pagination };
  return result;
}

interface SearchResultsProps {
  readonly children: ReactNode;
  readonly initialOrder: SearchOrder;
  readonly initialPagination: SearchPagination;
  readonly allRegions: Tables<"region_used">[];
  readonly allActivityCategories: Tables<"activity_category_used">[];
  readonly allStatuses: Tables<"status">[];
  readonly allUnitSizes: Tables<"unit_size">[];
  readonly allDataSources: Tables<"data_source">[];
  readonly initialUrlSearchParamsDict: URLSearchParamsDict;
}


export function SearchResults({
  children,
  initialOrder,
  initialPagination,
  allRegions,
  allActivityCategories,
  allStatuses,
  allUnitSizes,
  allDataSources,
  initialUrlSearchParamsDict,
}: SearchResultsProps) {
  const { selectedTimeContext } = useTimeContext();
  const initialUrlSearchParams = toURLSearchParams(initialUrlSearchParamsDict);
  const { externalIdentTypes, statDefinitions } = useBaseData();

  let emptySearchState = {
    order: initialOrder,
    pagination: initialPagination,
    apiSearchParams: {},
    valid_on: selectedTimeContext !== null ? selectedTimeContext?.valid_on : new Date().toISOString().split('T')[0],
    appSearchParams: {},
  } as SearchState

  let initialSearchState = initializeSearchStateFromUrlSearchParams(
    modifySearchStateReducer,
    emptySearchState,
    initialUrlSearchParams,
    externalIdentTypes?.[0],
    statDefinitions,
    allDataSources,
  );

  const [searchState, modifySearchState] = useReducer(modifySearchStateReducer, initialSearchState);


  const { order, pagination, apiSearchParams } = searchState;

  const derivedApiSearchParams = useMemo(() => {
    const params = new URLSearchParams();
    Object.entries(apiSearchParams).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });

    if (selectedTimeContext) {
      params.set("valid_from", `lte.${selectedTimeContext.valid_on}`);
      params.set("valid_to", `gte.${selectedTimeContext.valid_on}`);
    }

    if (order.name) {
      const externalIdentType = externalIdentTypes.find(type => type.code === order.name);
      const statDefinition = statDefinitions.find(identifier => identifier.code === order.name);

      if (externalIdentType) {
        params.set("order", `external_idents->>${order.name}.${order.direction}`);
      } else if (statDefinition) {
        params.set("order", `stats_summary->${order.name}->sum.${order.direction}`);
      } else {
        params.set("order", `${order.name}.${order.direction}`);
      }
    }

    if (pagination.pageNumber && pagination.pageSize) {
      const offset = (pagination.pageNumber - 1) * pagination.pageSize;
      params.set("limit", `${pagination.pageSize}`);
      params.set("offset", `${offset}`);
    }
    return params;
  }, [apiSearchParams, externalIdentTypes, order.direction, order.name, pagination.pageNumber, pagination.pageSize, selectedTimeContext, statDefinitions]);

  const { data: searchResult, error, isLoading } = useSWR<SearchResult>(
    `/api/search?${derivedApiSearchParams}`,
    (url) => fetcher(derivedApiSearchParams),
    { keepPreviousData: true, revalidateOnFocus: false }
  );

  const ctx: SearchContextState = useMemo(
    () =>
      ({
        searchState,
        modifySearchState,
        searchResult,
        derivedApiSearchParams,
        allRegions: allRegions ?? [],
        allActivityCategories: allActivityCategories ?? [],
        allStatuses: allStatuses ?? [],
        allUnitSizes: allUnitSizes ?? [],
        allDataSources: allDataSources ?? [],
        selectedTimeContext,
        isLoading,
        error,
      }) as SearchContextState,
    [
      searchState,
      searchResult,
      derivedApiSearchParams,
      allRegions,
      allActivityCategories,
      allStatuses,
      allUnitSizes,
      allDataSources,
      selectedTimeContext,
      isLoading,
      error,
    ]
  );

  useDerivedUrlSearchParams(ctx);

  return (
    <SearchContext.Provider value={ctx}>
      <TableColumnsProvider>
        {children}
      </TableColumnsProvider>
    </SearchContext.Provider>
  );
}
