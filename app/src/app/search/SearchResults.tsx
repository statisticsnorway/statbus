"use client";

import { ReactNode, useMemo, useReducer } from "react";
import { useTimeContext } from "@/app/time-context";
import useSWR from "swr";
import { searchFilterReducer } from "@/app/search/search-filter-reducer";
import useUpdatedUrlSearchParams from "@/app/search/use-updated-url-search-params";
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
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
  readonly regions: Tables<"region_used">[] | null;
  readonly activityCategories: Tables<"activity_category_used">[] | null;
  readonly urlSearchParams: URLSearchParams;
}

export default function SearchResults({
  children,
  order: initialOrder,
  pagination,
  regions,
  activityCategories,
  urlSearchParams,
}: SearchResultsProps) {
  const { selectedTimeContext } = useTimeContext();

  /**
   * Extract values from URLSearchParams and initialize search state.
   * This is not strictly necessary, but gives a more responsive UI when the search page filters are loaded
   */
    const valuesFromUrlSearchParams = useMemo(() => {
      const params = new URLSearchParams(urlSearchParams);
      return Array.from(params.keys()).reduce(
        (acc, key) => ({ ...acc, [key]: params.get(key)?.split(",") }),
        {}
      );
    }, [urlSearchParams]);

  const [search, dispatch] = useReducer(searchFilterReducer, {
    order: initialOrder,
    pagination,
    queries: {},
    timeContext: selectedTimeContext,
    values: valuesFromUrlSearchParams,
  });



  const { order, pagination: searchPagination, queries } = search;

  const searchParams = useMemo(() => {
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
    `/api/search?${searchParams}`,
    fetcher,
    { keepPreviousData: true, revalidateOnFocus: false }
  );

  const ctx: SearchContextState = useMemo(
    () => ({
      search,
      dispatch,
      searchResult,
      searchParams,
      regions: regions ?? [],
      activityCategories: activityCategories ?? [],
      selectedTimeContext,
      isLoading,
    }),
    [search, searchResult, searchParams, regions, activityCategories, selectedTimeContext, isLoading]
  );

  useUpdatedUrlSearchParams(ctx);

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
