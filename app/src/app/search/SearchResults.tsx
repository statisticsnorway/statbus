"use client";

import { ReactNode, useMemo, useReducer } from "react";
import { useTimeContext } from "@/app/time-context";
import useSWR from "swr";
import { modifySearchStateReducer } from "@/app/search/search-filter-reducer";
import useDerivedUrlSearchParams from "@/app/search/use-updated-url-search-params";
import { SearchContext, SearchContextState } from "@/app/search/search-context";
import { SearchResult, SearchOrder, SearchPagination } from "./search.d"; // Import necessary types
import type { Tables } from "@/lib/database.types";

const fetcher = async (url: string) => {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Error: ${response.status} ${response.statusText}`);
    }
    return await response.json();
  } catch (error) {
    console.error("Failed to fetch data:", error);
    throw error;
  }
};

interface SearchResultsProps {
  readonly children: ReactNode;
  readonly initialOrder: SearchOrder;
  readonly initialPagination: SearchPagination;
  readonly regions: Tables<"region_used">[];
  readonly activityCategories: Tables<"activity_category_used">[];
  readonly initialUrlSearchParams: URLSearchParams;
}

export default function SearchResults({
  children,
  initialOrder,
  initialPagination,
  regions,
  activityCategories,
  initialUrlSearchParams,
}: SearchResultsProps) {
  const { selectedTimeContext } = useTimeContext();

  /**
   * Extract values from URLSearchParams and initialize search state.
   * This is not strictly necessary, but gives a more responsive UI when the search page filters are loaded
   */
    const valuesFromUrlSearchParams = useMemo(() => {
      return Array.from(initialUrlSearchParams.keys()).reduce(
        (acc, key) => ({ ...acc, [key]: initialUrlSearchParams.get(key)?.split(",") }),
        {}
      );
    }, [initialUrlSearchParams]);

  const [searchState, modifySearchState] = useReducer(modifySearchStateReducer, {
    order: initialOrder,
    pagination: initialPagination,
    queries: {},
    timeContext: selectedTimeContext,
    values: valuesFromUrlSearchParams,
  });



  const { order, pagination: searchPagination, queries } = searchState;

  const derivedUrlSearchParams = useMemo(() => {
    const params = new URLSearchParams();
    Object.entries(queries).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });

    if (selectedTimeContext) {
      params.set("valid_from", `lte.${selectedTimeContext.valid_on}`);
      params.set("valid_to", `gte.${selectedTimeContext.valid_on}`);
    }

    if (order.name) {
      params.set("order", `${order.name}.${order.direction}`);
    }

    if (searchPagination.pageNumber && searchPagination.pageSize) {
      const offset = (searchPagination.pageNumber - 1) * searchPagination.pageSize;
      params.set("limit", `${searchPagination.pageSize}`);
      params.set("offset", `${offset}`);
    }
    return params;
  }, [queries, order, searchPagination, selectedTimeContext]);

  const { data: searchResult, error, isLoading } = useSWR<SearchResult>(
    `/api/search?${derivedUrlSearchParams}`,
    fetcher,
    { keepPreviousData: true, revalidateOnFocus: false }
  );

  const ctx: SearchContextState = useMemo(
    () => ({
      searchState,
      modifySearchState,
      searchResult,
      derivedUrlSearchParams,
      regions: regions ?? [],
      activityCategories: activityCategories ?? [],
      selectedTimeContext,
      isLoading,
    } as SearchContextState),
    [searchState, searchResult, derivedUrlSearchParams, regions, activityCategories, selectedTimeContext, isLoading]
  );

  useDerivedUrlSearchParams(ctx);

  if (isLoading) {
    return <div>Loading...</div>;
  }

  if (error) {
    return <div>Error loading data</div>;
  }

  return (
    <SearchContext.Provider value={ctx}>
      {children}
    </SearchContext.Provider>
  );
}
