"use client";

"use client";

import { ReactNode, useMemo, useReducer } from "react";
import { useTimeContext } from "@/app/time-context";
import useSWR from "swr";
import { searchFilterReducer } from "@/app/search/search-filter-reducer";
import useUpdatedUrlSearchParams from "@/app/search/use-updated-url-search-params";
import { SearchContext, SearchContextState } from "@/app/search/search-context";
import { SearchState, SearchResult, SearchOrder, SearchPagination } from "./search.d"; // Import necessary types
import type { Tables } from "@/lib/database.types";

const fetcher = (url: string) => fetch(url).then((res) => res.json());

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

  // Early return if no time context is available
  if (!selectedTimeContext) {
    return <div>No time context available</div>;
  }

  const [search, dispatch] = useReducer(searchFilterReducer, {
    order: initialOrder,
    pagination,
    queries: {},
    values: useMemo(() => {
      const params = new URLSearchParams(urlSearchParams);
      return Array.from(params.keys()).reduce(
        (acc, key) => ({ ...acc, [key]: params.get(key)?.split(",") }),
        {}
      );
    }, [urlSearchParams]),
  });

  const { order, pagination: searchPagination, queries } = search;

  const searchParams = useMemo(() => {
    const params = new URLSearchParams();
    Object.entries(queries).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });

    params.set("valid_from", `lte.${selectedTimeContext.valid_on}`);
    params.set("valid_to", `gte.${selectedTimeContext.valid_on}`);

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

  const { data, error } = useSWR<SearchResult>(
    `/api/statistical-units?${searchParams}`,
    fetcher,
    { keepPreviousData: true, revalidateOnFocus: false }
  );

  const ctx: SearchContextState = useMemo(
    () => ({
      search,
      dispatch,
      searchResult: data,
      searchParams,
      regions: regions ?? [],
      activityCategories: activityCategories ?? [],
      selectedTimeContext,
      isLoading: !data && !error,
    }),
    [search, data, searchParams, regions, activityCategories, error, selectedTimeContext]
  );

  useUpdatedUrlSearchParams(ctx);

  if (error) {
    return <div>Error loading data</div>;
  }

  if (!data) {
    return <div>Loading...</div>;
  }

  return (
    <SearchContext.Provider value={ctx}>
      {children}
    </SearchContext.Provider>
  );
}
