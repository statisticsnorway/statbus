import { useEffect } from "react";
// import { SearchContextState } from "@/app/search/search-context"; // Removed
import { useRouter } from "next/navigation";
import { useSearch } from "@/atoms/hooks"; // Import useSearch for Jotai state
import { SEARCH } from "./filters/url-search-params"; // AI: Import SEARCH constant

// TODO: This hook needs to be re-evaluated.
// It previously took SearchContextState. Now it should derive from Jotai's searchStateAtom.
// The structure of appSearchParams, order, pagination from old context vs.
// searchState.filters, searchState.sorting, searchState.pagination from Jotai is different.
export default function useDerivedUrlSearchParams(
  // searchState: SearchContextState // Old type, to be replaced
) {
  const router = useRouter();
  const { searchState: jotaiSearchState } = useSearch(); // Get Jotai search state
  const isSearchStateInitialized = useAtomValue(searchStateInitializedAtom); // Get initialization status

  useEffect(() => {
    if (!isSearchStateInitialized) {
      return; // Don't update URL if Jotai state hasn't been initialized from URL yet
    }

    const newGeneratedParams = new URLSearchParams();
    
    // Handle query
    if (jotaiSearchState.query && jotaiSearchState.query.trim() !== '') {
      newGeneratedParams.set(SEARCH, jotaiSearchState.query);
    }

    // Handle filters
    Object.entries(jotaiSearchState.filters).forEach(([name, values]) => {
      if (Array.isArray(values) && values.length > 0) {
        // Filter out null/empty strings if necessary, then join
        const validValues = values.filter(v => v !== null && v !== '').join(",");
        if (validValues.length > 0) {
          newGeneratedParams.set(name, validValues);
        }
      } else if (typeof values === 'string' && values.length > 0) {
        newGeneratedParams.set(name, values);
      } else if (values === null) {
        // Explicitly setting "null" if that's the desired representation in URL for cleared filters
        // Or, omit if null means the parameter should not be present.
        // Based on current logic, it seems "null" is sometimes used.
        // newGeneratedParams.set(name, "null"); // Let's assume null means absence for cleaner URLs unless specified
      }
    });
    
    // Handle sorting - only add if not default or if explicitly desired in URL
    if (jotaiSearchState.sorting.field && 
        (jotaiSearchState.sorting.field !== initialSearchStateValues.sorting.field || 
         jotaiSearchState.sorting.direction !== initialSearchStateValues.sorting.direction)) {
      newGeneratedParams.set("order", `${jotaiSearchState.sorting.field}.${jotaiSearchState.sorting.direction}`);
    }

    // Handle pagination - only add if not page 1
    if (jotaiSearchState.pagination.page && jotaiSearchState.pagination.page !== 1) {
      newGeneratedParams.set("page", `${jotaiSearchState.pagination.page}`);
    }
    // pageSize is usually not in URL unless it's configurable and different from default.
    // if (jotaiSearchState.pagination.pageSize !== initialSearchStateValues.pagination.pageSize) {
    //   newGeneratedParams.set("pageSize", `${jotaiSearchState.pagination.pageSize}`);
    // }

    const currentUrlParams = new URLSearchParams(window.location.search);
    
    // Sort params for stable comparison, as URLSearchParams.toString() does.
    newGeneratedParams.sort();
    currentUrlParams.sort();

    if (newGeneratedParams.toString() !== currentUrlParams.toString()) {
      router.replace(newGeneratedParams.size > 0 ? `?${newGeneratedParams}` : window.location.pathname, {
        scroll: false,
      });
    }
  }, [jotaiSearchState, router, isSearchStateInitialized]); // Add isSearchStateInitialized to deps

  // Old logic (commented out, will be removed once new logic is confirmed)
  /*
  const { appSearchParams, order, pagination } = contextState.searchState || {}; // Defensive access
  useEffect(() => {
    if (!appSearchParams || !order || !pagination) return; // Guard against undefined context parts

    const params = Object.entries(appSearchParams).reduce((params, [name, values]: [string, any]) => {
      if (!values?.length) return params;

      if (values[0] === null) {
        params.set(name, "null");
      } else {
        params.set(name, values.join(","));
      }

      return params;
    }, new URLSearchParams());

    if (order.name) {
      params.set("order", `${order.name}.${order.direction}`);
    }

    if (pagination.pageNumber) {
      params.set("page", `${pagination.pageNumber}`);
    }
    router.replace(params.size > 0 ? `?${params}` : window.location.pathname, {
      scroll: false,
    });
  }, [appSearchParams, order, pagination, router]);
  */
}
// Helper to access initialSearchStateValues from Jotai atoms index
import { initialSearchStateValues, searchStateInitializedAtom } from '@/atoms'; // Added searchStateInitializedAtom
import { useAtomValue } from 'jotai'; // Added useAtomValue
