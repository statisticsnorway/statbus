"use client";

import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAtomValue, useAtom } from "jotai";
import { useRouter } from "next/navigation";

import type { Tables } from "@/lib/database.types";
import {
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
  ACTIVITY_CATEGORY_PATH,
  REGION,
  SECTOR,
} from "../filters/url-search-params";

// This function derives a URL search string from state atoms.
// It is a pure function and is the single source of truth for State -> URL conversion.
type FullSearchState = { query: string; filters: Record<string, unknown>; pagination: SearchPagination; sorting: SearchSorting };

const deriveUrlFromState = (
  fullState: FullSearchState,
  externalIdentTypes: Tables<'external_ident_type_enabled'>[],
  statDefinitions: Tables<'stat_definition_enabled'>[]
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


// Writes the search state to the URL. Reading the URL into state is
// SearchResults' deriveStateFromUrl, the one URL -> state conversion; it sets
// searchStateInitializedAtom once it has run, and this hook writes only after
// that, so every filter the URL names (quality included) survives the round trip.
export function useSearchUrlSync() {
  const router = useRouter();
  const [isInitialized, setInitialized] = useAtom(searchStateInitializedAtom);

  const query = useAtomValue(queryAtom);
  const filters = useAtomValue(filtersAtom);
  const pagination = useAtomValue(paginationAtom);
  const sorting = useAtomValue(sortingAtom);
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);

  // Effect 1: Sync state to the URL after initialization and on subsequent changes
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

  // Effect 2: Reset initialization status on unmount.
  // This is critical for ensuring that if the user navigates away from the search
  // page and then returns (e.g., using the back button or a link from another
  // page), the state is re-initialized from the new URL search params.
  useGuardedEffect(() => {
    return () => {
      setInitialized(false);
    };
  }, [setInitialized], 'useSearchUrlSync:unmountReset');
}
