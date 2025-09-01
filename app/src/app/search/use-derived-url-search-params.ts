// import { SearchContextState } from "@/app/search/search-context"; // Removed
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { useSearch } from "@/atoms/search";
import {
  SEARCH,
  UNIT_TYPE, // Example, add other specific filter keys if needed for special handling
  REGION,
  SECTOR,
  ACTIVITY_CATEGORY_PATH,
} from "./filters/url-search-params";
import { searchStateInitializedAtom } from '@/atoms/app';
import { initialSearchStateValues } from '@/atoms/search';
import { externalIdentTypesAtom, statDefinitionsAtom } from '@/atoms/base-data';
import { useAtomValue } from 'jotai';
import { Tables } from "@/lib/database.types";

export default function useDerivedUrlSearchParams(initialUrlFromProps: string) {
  const router = useRouter();
  const { searchState: jotaiSearchState } = useSearch();
  const isSearchStateInitialized = useAtomValue(searchStateInitializedAtom);
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);

  useGuardedEffect(() => {
    if (!isSearchStateInitialized) {
      return; 
    }

    const newGeneratedParams = new URLSearchParams();

    // 1. Handle query
    if (jotaiSearchState.query && jotaiSearchState.query.trim() !== '') {
      newGeneratedParams.set(SEARCH, jotaiSearchState.query.trim());
    }

    // 2. Handle filters
    Object.entries(jotaiSearchState.filters).forEach(([name, appValue]) => {
      if (appValue === undefined) return;

      const isExternalIdent = externalIdentTypes.some((et: Tables<'external_ident_type_active'>) => et.code === name);
      const isStatVar = statDefinitions.some((sd: Tables<'stat_definition_active'>) => sd.code === name);
      const isPathBasedFilter = [REGION, SECTOR, ACTIVITY_CATEGORY_PATH].includes(name);

      if (Array.isArray(appValue)) {
        // Multi-value filters (e.g., UNIT_TYPE, STATUS) or path filters with "Missing" ([null])
        const stringValues = appValue
          .map(v => (v === null ? "null" : String(v)))
          .filter(v => v.length > 0);
        if (stringValues.length > 0) {
          newGeneratedParams.set(name, stringValues.join(","));
        }
      } else if (appValue === null && isPathBasedFilter) {
        // Single-select "Missing" for path filters if stored as `null` (not `[null]`)
        // This branch might be less common if UI components for path filters use `[null]` for "Missing"
        newGeneratedParams.set(name, "null");
      } else if (typeof appValue === 'string' && appValue.trim().length > 0) {
        // Single string values: external idents, stat vars ("op:val"), or single path selections
         newGeneratedParams.set(name, appValue.trim());
      }
      // If a filter value is an empty string (after trim for string types), or an empty array, it's omitted.
    });
    
    // 3. Handle sorting
    if (jotaiSearchState.sorting.field && 
        (jotaiSearchState.sorting.field !== initialSearchStateValues.sorting.field || 
         jotaiSearchState.sorting.direction !== initialSearchStateValues.sorting.direction)) {
      newGeneratedParams.set("order", `${jotaiSearchState.sorting.field}.${jotaiSearchState.sorting.direction}`);
    }

    // 4. Handle pagination
    if (jotaiSearchState.pagination.page && jotaiSearchState.pagination.page !== initialSearchStateValues.pagination.page) {
      newGeneratedParams.set("page", `${jotaiSearchState.pagination.page}`);
    }
    // pageSize is usually not in URL unless it's configurable and different from default.
    // if (jotaiSearchState.pagination.pageSize !== initialSearchStateValues.pagination.pageSize) {
    //   newGeneratedParams.set("pageSize", `${jotaiSearchState.pagination.pageSize}`);
    // }

    newGeneratedParams.sort(); // Sort for consistent string representation
    const paramsFromJotaiString = newGeneratedParams.toString();
    
    const initialUrlFromPropsSorted = new URLSearchParams(initialUrlFromProps);
    initialUrlFromPropsSorted.sort();
    const initialUrlFromPropsSortedString = initialUrlFromPropsSorted.toString();

    if (isSearchStateInitialized && paramsFromJotaiString !== initialUrlFromPropsSortedString) {
      // Jotai state has been initialized but is not yet consistent with the incoming URL.
      // This can happen if the effect runs before the Jotai state fully reflects the new props.
      // We must not update the browser URL with this potentially stale/intermediate Jotai state.
      return;
    }

    const currentWindowUrlParams = new URLSearchParams(window.location.search);
    currentWindowUrlParams.sort();
    const currentWindowUrlParamsString = currentWindowUrlParams.toString();

    if (paramsFromJotaiString !== currentWindowUrlParamsString) {
      router.replace(newGeneratedParams.size > 0 ? `?${newGeneratedParams}` : window.location.pathname, {
        scroll: false,
      });
    }
  }, [
    jotaiSearchState, 
    router, 
    isSearchStateInitialized, 
    initialUrlFromProps, 
    externalIdentTypes, 
    statDefinitions
  ], 'useDerivedUrlSearchParams:syncUrl');
}
