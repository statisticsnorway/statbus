import { useEffect } from "react";
// import { SearchContextState } from "@/app/search/search-context"; // Removed
import { useRouter } from "next/navigation";
import { useSearch } from "@/atoms/hooks"; // Import useSearch for Jotai state

// TODO: This hook needs to be re-evaluated.
// It previously took SearchContextState. Now it should derive from Jotai's searchStateAtom.
// The structure of appSearchParams, order, pagination from old context vs.
// searchState.filters, searchState.sorting, searchState.pagination from Jotai is different.
export default function useDerivedUrlSearchParams(
  // searchState: SearchContextState // Old type, to be replaced
  // For now, let's make it compatible with how SearchResults.tsx calls it,
  // but acknowledge it needs a proper refactor or might be obsolete.
  // The `ctx` object passed from SearchResults.tsx is the main issue.
  // If SearchResults.tsx stops creating/passing `ctx`, this hook's signature and logic must change.
  // For now, to fix the direct TS error, we remove the import and type.
  // This will cause `appSearchParams`, `order`, `pagination` to be errors.
  contextState: any // Temporary any to avoid breaking SearchResults.tsx call immediately
) {
  const router = useRouter();
  const { searchState: jotaiSearchState } = useSearch(); // Get Jotai search state

  useEffect(() => {
    // New logic based on jotaiSearchState
    const params = new URLSearchParams();
    
    // Handle query
    if (jotaiSearchState.query) {
      params.set("q", jotaiSearchState.query); // Assuming 'q' for query, adjust as needed
    }

    // Handle filters
    Object.entries(jotaiSearchState.filters).forEach(([name, values]) => {
      if (Array.isArray(values) && values.length > 0) {
        params.set(name, values.join(","));
      } else if (typeof values === 'string' && values.length > 0) {
        params.set(name, values);
      } else if (values === null) {
        params.set(name, "null");
      }
    });
    
    // Handle sorting
    if (jotaiSearchState.sorting.field) {
      params.set("order", `${jotaiSearchState.sorting.field}.${jotaiSearchState.sorting.direction}`);
    }

    // Handle pagination
    if (jotaiSearchState.pagination.page) {
      params.set("page", `${jotaiSearchState.pagination.page}`);
      // pageSize is usually not in URL unless it's configurable by user via URL
      // params.set("pageSize", `${jotaiSearchState.pagination.pageSize}`);
    }

    router.replace(params.size > 0 ? `?${params}` : window.location.pathname, {
      scroll: false,
    });
  }, [jotaiSearchState, router]);

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
