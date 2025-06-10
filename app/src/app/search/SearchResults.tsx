"use client";

import { ReactNode, useMemo, useEffect } from "react";
import { useTimeContext, useBaseData, useSearch } from "@/atoms/hooks";
import { useSetAtom, useAtomValue } from 'jotai';
import useSWR from "swr";
import useDerivedUrlSearchParams from "@/app/search/use-derived-url-search-params";
// import { SearchContext, SearchContextState } from "./search-context"; // Removed as per migration
import { SearchResult as ApiSearchResultType, SearchOrder, SearchPagination } from "./search.d";
import { searchResultAtom, derivedApiSearchParamsAtom, searchStateAtom, setSearchPageDataAtom, searchStateInitializedAtom } from '@/atoms'; // AI: Added searchStateInitializedAtom
import type { Tables } from "@/lib/database.types";
import { toURLSearchParams, URLSearchParamsDict } from "@/lib/url-search-params-dict";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { getStatisticalUnits } from "./search-requests";
import {
  SEARCH,
  UNIT_TYPE,
  // AI: Moved the misplaced import block here
  fullTextSearchDeriveStateUpdateFromSearchParams,
  unitTypeDeriveStateUpdateFromSearchParams,
  invalidCodesDeriveStateUpdateFromSearchParams,
  legalFormDeriveStateUpdateFromSearchParams,
  regionDeriveStateUpdateFromSearchParams,
  sectorDeriveStateUpdateFromSearchParams,
  activityCategoryDeriveStateUpdateFromSearchParams,
  statusDeriveStateUpdateFromSearchParams,
  unitSizeDeriveStateUpdateFromSearchParams,
  dataSourceDeriveStateUpdateFromSearchParams,
  externalIdentDeriveStateUpdateFromSearchParams,
  statisticalVariablesDeriveStateUpdateFromSearchParams,
  // End of moved block
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SECTOR,
  ACTIVITY_CATEGORY_PATH,
  STATUS,
  UNIT_SIZE,
  DATA_SOURCE,
  // No need for the individual `*DeriveStateUpdateFromSearchParams` functions here
  // as we'll call Jotai setters directly.
} from "./filters/url-search-params";
import { SearchAction } from "./search.d"; // AI: Moved this import too
import { useAtom } from "jotai"; // AI: Moved this import too

// SWR Fetcher - kept local as it's specific to SWR's usage here
const fetcherForSWR = async (paramsString: string) => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available for SWR search");
  try {
    // paramsString already includes the leading '?' from `/api/search?${...}`
    // so we create URLSearchParams from the part after '?'
    const actualParams = new URLSearchParams(paramsString.substring(paramsString.indexOf('?') + 1));
    const response = await getStatisticalUnits(client, actualParams);
    return response;
  } catch (error) {
    console.error("SWR fetcher failed for search:", error);
    throw error;
  }
};

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
  const initialUrlSearchParams = useMemo(() => toURLSearchParams(initialUrlSearchParamsDict), [initialUrlSearchParamsDict]);
  const { externalIdentTypes, statDefinitions } = useBaseData();
  const setSearchPageData = useSetAtom(setSearchPageDataAtom);
  const [, setSearchState] = useAtom(searchStateAtom); // Get the setter for the entire searchStateAtom

  // const {
  //   searchState: jotaiSearchState, // Not needed directly if we set the whole state
  //   updateSearchQuery, // Not needed if setting whole state
  //   updateFilters, // Not needed if setting whole state
  //   updatePagination, // Not needed if setting whole state
  //   updateSorting, // Not needed if setting whole state
  //   executeSearch, // Still needed if we want to trigger explicit search after init
  // } = useSearch(); // We might not need to destructure all of these if setting state directly

  const setGlobalSearchResult = useSetAtom(searchResultAtom);
  const derivedApiParamsFromJotai = useAtomValue(derivedApiSearchParamsAtom);
  const setSearchStateInitialized = useSetAtom(searchStateInitializedAtom);

  // Initialize Jotai search state from props and URL on mount
  useEffect(() => {
    setSearchStateInitialized(false); // Reset initialization flag

    // 1. Gather all SearchActions from URL parameters
    const ftsAction = fullTextSearchDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const unitTypeAction = unitTypeDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const invalidCodesAction = invalidCodesDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const legalFormAction = legalFormDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const regionAction = regionDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const sectorAction = sectorDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const activityCategoryAction = activityCategoryDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const statusAction = statusDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    const unitSizeAction = unitSizeDeriveStateUpdateFromSearchParams(initialUrlSearchParams);
    // Pass allDataSources (from props) to dataSourceDeriveStateUpdateFromSearchParams
    const dataSourceAction = dataSourceDeriveStateUpdateFromSearchParams(initialUrlSearchParams, allDataSources);

    const externalIdentActions = externalIdentTypes.map(extType =>
      externalIdentDeriveStateUpdateFromSearchParams(extType, initialUrlSearchParams)
    );
    const statVarActions = statisticalVariablesDeriveStateUpdateFromSearchParams(statDefinitions, initialUrlSearchParams);

    const allActions = [
      ftsAction, unitTypeAction, invalidCodesAction, legalFormAction, regionAction,
      sectorAction, activityCategoryAction, statusAction, unitSizeAction, dataSourceAction,
      ...externalIdentActions, ...statVarActions
    ].filter(Boolean) as SearchAction[];

    // 2. Construct initial query and filters for Jotai state
    let newInitialQuery = '';
    const newInitialFilters: Record<string, any> = {};

    allActions.forEach(action => {
      const { app_param_name, app_param_values } = action.payload;
      if (app_param_name === SEARCH) {
        newInitialQuery = app_param_values[0] || '';
      } else {
        const isExternalIdent = externalIdentTypes.some(et => et.code === app_param_name);
        const isStatVar = statDefinitions.some(sd => sd.code === app_param_name);

        if (isExternalIdent) {
          // External idents are stored as single strings in searchState.filters
          newInitialFilters[app_param_name] = app_param_values[0] || undefined;
        } else if (isStatVar) {
          // Stat vars are "op:val" strings in searchState.filters.
          // app_param_values from SearchAction is ["op.val"].
          const val = app_param_values[0];
          if (val) {
            newInitialFilters[app_param_name] = val.replace('.', ':');
          } else {
            newInitialFilters[app_param_name] = undefined;
          }
        } else {
          // Other filters (UNIT_TYPE, REGION, etc.) are stored as string arrays.
          // app_param_values is already (string | null)[].
          // Filter out nulls if the specific filter doesn't expect them, or keep if it does (e.g. "Missing" option)
          newInitialFilters[app_param_name] = app_param_values.filter(v => v !== ''); // Filter empty strings, keep nulls for "Missing"
        }
      }
    });

    // 3. Construct the full initial search state
    const newFullInitialSearchState: SearchState = {
      query: newInitialQuery,
      filters: newInitialFilters,
      pagination: { page: initialPagination.pageNumber, pageSize: initialPagination.pageSize },
      sorting: { field: initialOrder.name, direction: initialOrder.direction },
    };

    // 4. Set the entire searchStateAtom once
    setSearchState(newFullInitialSearchState);
    setSearchStateInitialized(true); // Signal that initialization is complete

  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    initialUrlSearchParams, initialOrder.name, initialOrder.direction,
    initialPagination.pageNumber, initialPagination.pageSize,
    externalIdentTypes, statDefinitions, allDataSources, // Added allDataSources
    setSearchState, setSearchStateInitialized // Jotai setters
  ]);

  // Effect to set the initial allXxx data into Jotai state
  useEffect(() => {
    setSearchPageData({
      allRegions,
      allActivityCategories,
      allStatuses,
      allUnitSizes,
      allDataSources,
    });
  }, [allRegions, allActivityCategories, allStatuses, allUnitSizes, allDataSources, setSearchPageData]);

  // SWR for data fetching, key is derived from Jotai's derivedApiSearchParamsAtom
  const derivedApiParamsString = derivedApiParamsFromJotai.toString();
  const swrKey = derivedApiParamsString ? `/api/search?${derivedApiParamsString}` : null; // Prevent fetch if params are empty initially

  const { data: swrData, error: swrError, isLoading: swrIsLoading } = useSWR<ApiSearchResultType>(
    swrKey, // SWR key now depends on Jotai state via derivedApiParamsFromJotai
    fetcherForSWR, // Use the local fetcher for SWR
    { keepPreviousData: true, revalidateOnFocus: false }
  );
  
  // Effect to sync SWR state to global Jotai searchResultAtom
  useEffect(() => {
    if (swrIsLoading) {
      setGlobalSearchResult(prev => ({ ...prev, loading: true, error: null }));
    } else if (swrError) {
      setGlobalSearchResult(prev => ({ 
        data: prev.data, // Optionally keep stale data on error
        total: prev.total, 
        loading: false, 
        error: (swrError as Error).message || 'Failed to fetch search results' 
      }));
    } else if (swrData) {
      setGlobalSearchResult({ 
        data: swrData.statisticalUnits, 
        total: swrData.count, 
        loading: false, 
        error: null 
      });
    }
  }, [swrData, swrError, swrIsLoading, setGlobalSearchResult]);

  const currentGlobalSearchResult = useAtomValue(searchResultAtom);

  // The ctx object and SearchContextState are remnants of the old context system and are no longer needed.
  // Consumers should use the useSearch() hook and other Jotai atoms/hooks directly.
  useDerivedUrlSearchParams(); // AI: Uncommented and call without arguments

  return (
    // <SearchContext.Provider value={ctx}> // Removed as per migration
    <>
      {children}
    </>
    // </SearchContext.Provider>
  );
}
