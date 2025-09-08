"use client";

import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSetAtom, useAtomValue, useAtom } from "jotai";
import { useRouter } from "next/navigation";
import { useMemo } from "react";
import { isEqual } from 'moderndash';

import type { Tables } from "@/lib/database.types";
import { type SearchAction } from "../search.d";
import {
  setSearchPageDataAtom,
  paginationAtom,
  type SearchPagination,
  sortingAtom,
  type SearchSorting,
  queryAtom,
  filtersAtom,
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
  const query = useAtomValue(queryAtom);
  const filters = useAtomValue(filtersAtom);
  const pagination = useAtomValue(paginationAtom);
  const sorting = useAtomValue(sortingAtom);
  const isInitialized = useAtomValue(searchStateInitializedAtom);
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  
  useGuardedEffect(() => {
    // This effect should only run AFTER the initial state hydration is complete.
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
}
