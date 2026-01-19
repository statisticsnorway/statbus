"use client";

import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSetAtom, useAtomValue, useAtom } from "jotai";
import { useRouter } from "next/navigation";
import { useMemo } from "react";
import { isEqual } from 'moderndash';

import type { Tables } from "@/lib/database.types";
import { type SearchAction } from "../search.d";
import {
  paginationAtom,
  type SearchPagination,
  sortingAtom,
  type SearchSorting,
  queryAtom,
  filtersAtom,
  searchPageDataAtom,
  type SearchDirection,
} from "@/atoms/search";
import { searchStateInitializedAtom } from "@/atoms/app";
import {
  externalIdentTypesAtom,
  statDefinitionsAtom,
} from "@/atoms/base-data";
import {
  SEARCH,
  activityCategoryDeriveStateUpdateFromSearchParams,
  dataSourceDeriveStateUpdateFromSearchParams,
  externalIdentDeriveStateUpdateFromSearchParams,
  fullTextSearchDeriveStateUpdateFromSearchParams,
  invalidCodesDeriveStateUpdateFromSearchParams,
  legalFormDeriveStateUpdateFromSearchParams,
  regionDeriveStateUpdateFromSearchParams,
  sectorDeriveStateUpdateFromSearchParams,
  statusDeriveStateUpdateFromSearchParams,
  domesticDeriveStateUpdateFromSearchParams,
  lastEditByUserDeriveStateUpdateFromSearchParams,
  statisticalVariablesDeriveStateUpdateFromSearchParams,
  unitSizeDeriveStateUpdateFromSearchParams,
  unitTypeDeriveStateUpdateFromSearchParams,
  ACTIVITY_CATEGORY_PATH,
  REGION,
  SECTOR,
} from "../filters/url-search-params";

interface UseSearchUrlSyncProps {
  initialUrlSearchParamsString: string;
  allRegions: Tables<"region_used">[];
  allActivityCategories: Tables<"activity_category_used">[];
  allStatuses: Tables<"status">[];
  allUnitSizes: Tables<"unit_size">[];
  allDataSources: Tables<"data_source">[];
}

// This function derives a URL search string from state atoms.
// It is a pure function and is the single source of truth for State -> URL conversion.
type FullSearchState = { query: string; filters: Record<string, any>; pagination: SearchPagination; sorting: SearchSorting };

const deriveUrlFromState = (
  fullState: FullSearchState,
  externalIdentTypes: Tables<'external_ident_type_active'>[],
  statDefinitions: Tables<'stat_definition_active'>[]
): string => {
  const newGeneratedParams = new URLSearchParams();

  if (fullState.query && fullState.query.trim() !== '') {
    newGeneratedParams.set(SEARCH, fullState.query.trim());
  }

  Object.entries(fullState.filters).forEach(([name, appValue]) => {
    if (appValue === undefined || (Array.isArray(appValue) && appValue.length === 0)) return;

    const isStatVar = statDefinitions.some(sd => sd.code === name);
    const isPathBasedFilter = [REGION, SECTOR, ACTIVITY_CATEGORY_PATH].includes(name);
    
    if (Array.isArray(appValue)) {
        const stringValues = appValue.map(v => (v === null ? "null" : String(v))).filter(v => v.length > 0);
        if (stringValues.length > 0) newGeneratedParams.set(name, stringValues.join(","));
    } else if (appValue === null && isPathBasedFilter) {
        newGeneratedParams.set(name, "null");
    } else if (typeof appValue === 'string' && appValue.trim().length > 0) {
        if (isStatVar) {
          newGeneratedParams.set(name, appValue.trim().replace(':', '.'));
        } else {
          newGeneratedParams.set(name, appValue.trim());
        }
    }
  });

  if (fullState.sorting.field) {
    newGeneratedParams.set("order", `${fullState.sorting.field}.${fullState.sorting.direction}`);
  }

  const { pagination } = fullState;
  // This is the definitive fix. By always including the page number, we prevent
  // an asymmetry where a URL with `page=1` would be "cleaned" to a URL without
  // a page number, causing a navigation loop.
  if (pagination.page) {
    newGeneratedParams.set("page", String(pagination.page));
  }
  
  newGeneratedParams.sort();
  return newGeneratedParams.toString();
};


export function useSearchUrlSync() {
  const router = useRouter();
  const [isInitialized, setInitialized] = useAtom(searchStateInitializedAtom);

  // State values and setters
  const [query, setQuery] = useAtom(queryAtom);
  const [filters, setFilters] = useAtom(filtersAtom);
  const [pagination, setPagination] = useAtom(paginationAtom);
  const [sorting, setSorting] = useAtom(sortingAtom);
  
  // Data required for parsing/deriving state
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  const { allDataSources } = useAtomValue(searchPageDataAtom);

  // Effect 1: Initialize state from URL on first load
  useGuardedEffect(() => {
    // Guard against running if already initialized or if essential data isn't loaded yet.
    if (isInitialized || !allDataSources.length || !externalIdentTypes.length) {
      return;
    }

    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.toString() === '') {
      // If there are no params, we are done initializing with default/stored state.
      setInitialized(true);
      return;
    }

    // Most ...fromSearchParams functions return a single action, but some can return multiple.
    const singleActions: (SearchAction | null)[] = [
      fullTextSearchDeriveStateUpdateFromSearchParams(urlParams),
      unitTypeDeriveStateUpdateFromSearchParams(urlParams),
      invalidCodesDeriveStateUpdateFromSearchParams(urlParams),
      legalFormDeriveStateUpdateFromSearchParams(urlParams),
      regionDeriveStateUpdateFromSearchParams(urlParams),
      sectorDeriveStateUpdateFromSearchParams(urlParams),
      activityCategoryDeriveStateUpdateFromSearchParams(urlParams),
      statusDeriveStateUpdateFromSearchParams(urlParams),
      domesticDeriveStateUpdateFromSearchParams(urlParams),
      lastEditByUserDeriveStateUpdateFromSearchParams(urlParams),
      unitSizeDeriveStateUpdateFromSearchParams(urlParams),
      dataSourceDeriveStateUpdateFromSearchParams(urlParams),
    ];

    // externalIdent... expects a single type object, so we must map over the available types.
    // It may return one or more actions, so we use flatMap.
    const externalIdentActions: (SearchAction | null)[] = externalIdentTypes.flatMap(
      (type) => externalIdentDeriveStateUpdateFromSearchParams(type, urlParams),
    );

    // statisticalVariables... expects an array of definitions and returns an array of actions.
    const statisticalVariableActions =
      statisticalVariablesDeriveStateUpdateFromSearchParams(
        statDefinitions,
        urlParams,
      );

    const actions: (SearchAction | null)[] = [
      ...singleActions,
      ...externalIdentActions,
      ...statisticalVariableActions,
    ];
    
    const newFilters: Record<string, any> = {};
    let newQuery: string | null = null;
    
    actions.forEach(action => {
      if (action?.type === 'set_query') {
        const values = action.payload.app_param_values;
        // Don't set state if values are missing or it's an empty array.
        if (!values || values.length === 0) {
          return;
        }

        if (action.payload.app_param_name === SEARCH) {
          // Full-text search is a single value.
          newQuery = values[0];
        } else {
          // Other filters can be single or multiple values, store as an array.
          newFilters[action.payload.app_param_name] = values;
        }
      }
    });

    setFilters(newFilters);
    if (newQuery !== null) setQuery(newQuery);

    const pageParam = urlParams.get('page');
    if (pageParam) {
      const page = parseInt(pageParam, 10);
      if (!isNaN(page)) setPagination(prev => ({ ...prev, page }));
    }

    const orderParam = urlParams.get('order');
    if (orderParam) {
      const [field, direction] = orderParam.split('.');
      if (field && direction) setSorting({ field, direction: direction as SearchDirection });
    }

    setInitialized(true);

  }, [isInitialized, allDataSources, externalIdentTypes, statDefinitions, setInitialized, setQuery, setFilters, setPagination, setSorting], 'useSearchUrlSync:initialize');

  // Effect 2: Sync state back to URL after initialization and on subsequent changes
  useGuardedEffect(() => {
    if (!isInitialized) {
      return;
    }

    const fullState = { query, filters, pagination, sorting };
    const urlFromState = deriveUrlFromState(fullState, externalIdentTypes, statDefinitions);
    
    const currentWindowUrlParams = new URLSearchParams(window.location.search);
    currentWindowUrlParams.sort();
    const currentWindowUrlParamsString = currentWindowUrlParams.toString();
    
    if (urlFromState !== currentWindowUrlParamsString) {
      router.replace(urlFromState ? `?${urlFromState}` : window.location.pathname, {
        scroll: false,
      });
    }
    
  }, [query, filters, pagination, sorting, router, isInitialized, externalIdentTypes, statDefinitions], 'useSearchUrlSync:sync');

  // Effect 3: Reset initialization status on unmount.
  // This is critical for ensuring that if the user navigates away from the search
  // page and then returns (e.g., using the back button or a link from another
  // page), the state is re-initialized from the new URL search params.
  useGuardedEffect(() => {
    return () => {
      setInitialized(false);
    };
  }, [setInitialized], 'useSearchUrlSync:unmountReset');
}
