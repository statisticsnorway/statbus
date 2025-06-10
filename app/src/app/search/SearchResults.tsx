"use client";

import { ReactNode, useMemo, useEffect } from "react";
import { useTimeContext, useBaseData, useSearch } from "@/atoms/hooks";
import { useSetAtom, useAtomValue } from 'jotai';
import useSWR from "swr";
import useDerivedUrlSearchParams from "@/app/search/use-derived-url-search-params";
// import { SearchContext, SearchContextState } from "./search-context"; // Removed as per migration
import { SearchResult as ApiSearchResultType, SearchOrder, SearchPagination } from "./search.d";
import { searchResultAtom, derivedApiSearchParamsAtom, searchStateAtom, setSearchPageDataAtom } from '@/atoms';
import type { Tables } from "@/lib/database.types";
import { toURLSearchParams, URLSearchParamsDict } from "@/lib/url-search-params-dict";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { getStatisticalUnits } from "./search-requests";
import {
  SEARCH,
  UNIT_TYPE,
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

  const {
    searchState: jotaiSearchState, // Renamed to avoid conflict with old context's searchState
    updateSearchQuery,
    updateFilters,
    updatePagination,
    updateSorting,
    executeSearch,
    // Destructure allXxx from useSearch, which now gets them from searchPageDataAtom
    allRegions: jotaiAllRegions,
    allActivityCategories: jotaiAllActivityCategories,
    allStatuses: jotaiAllStatuses,
    allUnitSizes: jotaiAllUnitSizes,
    allDataSources: jotaiAllDataSources,
  } = useSearch();

  const setGlobalSearchResult = useSetAtom(searchResultAtom);
  const derivedApiParamsFromJotai = useAtomValue(derivedApiSearchParamsAtom);

  // Initialize Jotai search state from props and URL on mount
  useEffect(() => {
    let initialFiltersInternal: Record<string, any> = {};
    
    // Full-text search
    const queryParam = initialUrlSearchParams.get(SEARCH); // Use imported constant
    updateSearchQuery(queryParam || ''); 

    // Helper to get single or all values for a param
    const getParamValue = (key: string, getAll: boolean = false) => {
      if (getAll) {
        const values = initialUrlSearchParams.getAll(key);
        return values.length > 0 ? values : undefined;
      }
      return initialUrlSearchParams.get(key) || undefined;
    };
    
    const filterMappings: { key: string, paramConst: string, isMulti?: boolean }[] = [
      { key: UNIT_TYPE, paramConst: UNIT_TYPE },
      { key: INVALID_CODES, paramConst: INVALID_CODES, isMulti: true },
      { key: LEGAL_FORM, paramConst: LEGAL_FORM, isMulti: true },
      { key: REGION, paramConst: REGION },
      { key: SECTOR, paramConst: SECTOR },
      { key: ACTIVITY_CATEGORY_PATH, paramConst: ACTIVITY_CATEGORY_PATH },
      { key: STATUS, paramConst: STATUS, isMulti: true },
      { key: UNIT_SIZE, paramConst: UNIT_SIZE, isMulti: true },
      { key: DATA_SOURCE, paramConst: DATA_SOURCE, isMulti: true },
    ];

    filterMappings.forEach(mapping => {
      const val = getParamValue(mapping.paramConst, mapping.isMulti);
      if (val !== undefined) initialFiltersInternal[mapping.key] = val;
    });

    // External Identifiers
    externalIdentTypes.forEach(extIdentType => {
      const extIdentVal = initialUrlSearchParams.get(extIdentType.code!); 
      if (extIdentVal) {
        initialFiltersInternal[extIdentType.code!] = extIdentVal;
      }
    });
    
    // Statistical Variables
    statDefinitions.forEach(statDef => {
      const statVarVal = initialUrlSearchParams.get(statDef.code!); 
      if (statVarVal) {
        // Assuming the value is already in "operator:operand" format if needed, or just plain value
        initialFiltersInternal[statDef.code!] = statVarVal; 
      }
    });
    
    updateFilters(initialFiltersInternal);
    // Adapt to new pagination structure in Jotai state (page vs pageNumber)
    updatePagination(initialPagination.pageNumber, initialPagination.pageSize); 
    updateSorting(initialOrder.name, initialOrder.direction);

    // Initial fetch is triggered because derivedApiSearchParamsAtom will change due to above updates,
    // and swrKey depends on it. executeSearch() can be called if explicit trigger is desired
    // after all initial state is set.
    // For clarity and to ensure it runs after all Jotai state updates are processed:
    // setTimeout(executeSearch, 0); // or a more robust way to ensure state is settled.
    // However, SWR's nature of re-fetching on key change should handle this.
    // Let's rely on SWR's key change for now. If an explicit fetch is needed, executeSearch() is available.

  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    initialUrlSearchParams, initialOrder.name, initialOrder.direction,
    initialPagination.pageNumber, initialPagination.pageSize,
    externalIdentTypes, statDefinitions,
    // Jotai setters are stable and don't need to be in deps
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
  // useDerivedUrlSearchParams(ctx); // This call was dependent on ctx and needs re-evaluation if its functionality is still required.
  // For now, it's commented out as ctx is removed.

  return (
    // <SearchContext.Provider value={ctx}> // Removed as per migration
    <>
      {children}
    </>
    // </SearchContext.Provider>
  );
}
