"use client";

import { ReactNode, useMemo } from "react";
import { isEqual } from "moderndash";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSetAtom, useAtomValue, useAtom } from 'jotai';
import { derivedApiSearchParamsAtom, performSearchAtom, setSearchPageDataAtom, paginationAtom, type SearchPagination, sortingAtom, SearchSorting, queryAtom, filtersAtom } from '@/atoms/search';
import { searchStateInitializedAtom } from "@/atoms/app";
import { externalIdentTypesAtom, statDefinitionsAtom, baseDataAtom } from "@/atoms/base-data";
import type { Tables } from "@/lib/database.types";
import { useSearchUrlSync } from "./hooks/useSearchUrlSync";
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
  lastEditByUserDeriveStateUpdateFromSearchParams,
  statisticalVariablesDeriveStateUpdateFromSearchParams,
  unitSizeDeriveStateUpdateFromSearchParams,
  unitTypeDeriveStateUpdateFromSearchParams,
} from "./filters/url-search-params";
import { SearchAction } from "./search.d";

interface SearchResultsProps {
  readonly children: ReactNode;
  readonly allRegions: Tables<"region_used">[];
  readonly allActivityCategories: Tables<"activity_category_used">[];
  readonly allStatuses: Tables<"status">[];
  readonly allUnitSizes: Tables<"unit_size">[];
  readonly allDataSources: Tables<"data_source_used">[];
  readonly allExternalIdentTypes: Tables<"external_ident_type_active">[];
  readonly allLegalForms: Tables<"legal_form_used">[];
  readonly allSectors: Tables<"sector_used">[];
  readonly initialUrlSearchParamsString: string;
}

// This function derives a complete SearchState object from a URLSearchParams object.
// It is a pure function and is the single source of truth for URL -> State conversion.
const deriveStateFromUrl = (
  urlSearchParams: URLSearchParams,
  externalIdentTypes: Tables<'external_ident_type_active'>[],
  statDefinitions: Tables<'stat_definition_active'>[]
): { _initialQuery: string; _initialFilters: Record<string, any>; _initialPagination: SearchPagination; _initialSorting: SearchSorting } => {

  const ftsAction = fullTextSearchDeriveStateUpdateFromSearchParams(urlSearchParams);
  const unitTypeAction = unitTypeDeriveStateUpdateFromSearchParams(urlSearchParams);
  const invalidCodesAction = invalidCodesDeriveStateUpdateFromSearchParams(urlSearchParams);
  const legalFormAction = legalFormDeriveStateUpdateFromSearchParams(urlSearchParams);
  const regionAction = regionDeriveStateUpdateFromSearchParams(urlSearchParams);
  const sectorAction = sectorDeriveStateUpdateFromSearchParams(urlSearchParams);
  const activityCategoryAction = activityCategoryDeriveStateUpdateFromSearchParams(urlSearchParams);
  const statusAction = statusDeriveStateUpdateFromSearchParams(urlSearchParams);
  const lastEditByUserAction =
    lastEditByUserDeriveStateUpdateFromSearchParams(urlSearchParams);
  const unitSizeAction =
    unitSizeDeriveStateUpdateFromSearchParams(urlSearchParams);
  const dataSourceAction =
    dataSourceDeriveStateUpdateFromSearchParams(urlSearchParams);
  const externalIdentActions = externalIdentTypes.map((extType) =>
    externalIdentDeriveStateUpdateFromSearchParams(extType, urlSearchParams)
  );
  const statVarActions = statisticalVariablesDeriveStateUpdateFromSearchParams(
    statDefinitions,
    urlSearchParams
  );

  const allActions = [
    ftsAction,
    unitTypeAction,
    invalidCodesAction,
    legalFormAction,
    regionAction,
    sectorAction,
    activityCategoryAction,
    statusAction,
    lastEditByUserAction,
    unitSizeAction,
    dataSourceAction,
    ...externalIdentActions,
    ...statVarActions,
  ].filter(Boolean) as SearchAction[];

  let newInitialQuery = '';
  const newInitialFilters: Record<string, any> = {};

  allActions.forEach(action => {
    if (action.type === 'set_query') {
      const { app_param_name, app_param_values } = action.payload;
      if (app_param_name === SEARCH) {
        // This is the definitive fix. By trimming the query here, we make the
        // URL parsing logic symmetrical with the URL serialization logic, which
        // also trims the query. This prevents the infinite loop.
        newInitialQuery = (app_param_values[0] || '').trim();
      } else {
        const isExternalIdent = externalIdentTypes.some(et => et.code === app_param_name);
        const isStatVar = statDefinitions.some(sd => sd.code === app_param_name);

        if (isExternalIdent) {
          const value = app_param_values[0];
          // Only set the filter if the value is a non-empty string.
          // This prevents `?orgnr=` from creating `{ orgnr: "" }` in the state.
          if (value) { 
            newInitialFilters[app_param_name] = value;
          }
        } else if (isStatVar) {
          const val = app_param_values[0];
          // Only set the filter if the value is a non-empty string.
          if (val) {
            newInitialFilters[app_param_name] = val.replace('.', ':');
          }
        } else {
          newInitialFilters[app_param_name] = app_param_values.filter((v) => v !== '');
        }
      }
    }
  });

  let initialOrder: SearchSorting = { field: 'name', direction: 'asc' };
  const orderParam = urlSearchParams.get("order");
  if (orderParam) {
    const [orderBy, orderDirection] = orderParam.split(".");
    const validOrderDirection = orderDirection === "desc.nullslast" ? "desc.nullslast" : "asc";
    initialOrder = { field: orderBy, direction: validOrderDirection as "asc" | "desc.nullslast" };
  }

  const initialPagination = {
    page: Number(urlSearchParams.get("page")) || 1,
    pageSize: 10, // Default page size is now hardcoded here
  };

  // The pagination state is now handled by its own atom and is not returned here.
  // The `initializeState` effect will need to be updated to set it.
  return {
    _initialQuery: newInitialQuery,
    _initialFilters: newInitialFilters,
    _initialSorting: initialOrder,
    _initialPagination: initialPagination 
  };
};


export function SearchResults({
  children,
  allRegions,
  allActivityCategories,
  allStatuses,
  allUnitSizes,
  allDataSources,
  allExternalIdentTypes,
  allLegalForms,
  allSectors,
  initialUrlSearchParamsString,
}: SearchResultsProps) {
  const setFilters = useSetAtom(filtersAtom);
  const setQuery = useSetAtom(queryAtom);
  const [pagination, setPagination] = useAtom(paginationAtom); // Get setter for new atom
  const [sorting, setSorting] = useAtom(sortingAtom);
  const [isInitialized, setInitialized] = useAtom(searchStateInitializedAtom);
  const setSearchPageData = useSetAtom(setSearchPageDataAtom);
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);

  // This effect handles the one-time initialization from URL -> State.
  useGuardedEffect(() => {
    if (isInitialized) {
      return;
    }
    
    // 1. Set static page data (for filters, etc.)
    setSearchPageData({
      allRegions,
      allActivityCategories,
      allStatuses,
      allUnitSizes,
      allDataSources,
      allExternalIdentTypes,
      allLegalForms,
      allSectors,
    });
    
    // 2. Derive the initial state from the URL string prop.
    const initialUrlSearchParams = new URLSearchParams(initialUrlSearchParamsString);
    const { _initialPagination, _initialSorting, _initialQuery, _initialFilters } = deriveStateFromUrl(initialUrlSearchParams, externalIdentTypes, statDefinitions);
    
    // 3. Atomically set the hydrated state and mark initialization as complete.
    setQuery(_initialQuery);
    setFilters(_initialFilters);
    setSorting(_initialSorting);
    setPagination(_initialPagination);

    setInitialized(true);
  }, [
    isInitialized,
    setInitialized,
    initialUrlSearchParamsString,
    externalIdentTypes,
    statDefinitions,
    setQuery,
    setFilters,
    setPagination,
    setSorting,
    setSearchPageData,
    // The `all...` props are intentionally omitted, as are `pagination` and `sorting`.
    // This effect should only run when its true inputs (URL, base data) change.
  ], 'SearchResults:initializeState');

  useSearchUrlSync();

  const derivedApiParamsFromJotai = useAtomValue(derivedApiSearchParamsAtom);
  const performSearch = useSetAtom(performSearchAtom);
  
  // This effect remains to trigger the data fetch whenever the API params change.
  useGuardedEffect(() => {
    if (isInitialized && derivedApiParamsFromJotai.toString()) {
      performSearch();
    }
  }, [isInitialized, derivedApiParamsFromJotai, performSearch], 'SearchResults:directFetch');

  return (
    <>
      {children}
    </>
  );
}
