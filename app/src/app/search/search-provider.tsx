"use client";
import { ReactNode, useMemo, useReducer } from "react";
import { searchFilterReducer } from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/use-search";
import useUpdatedUrlSearchParams from "@/app/search/use-updated-url-search-params";
import { SearchContext, SearchContextState } from "@/app/search/search-context";
import type { Tables } from "@/lib/database.types";

interface SearchProviderProps {
  readonly children: ReactNode;
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
  readonly regions: Tables<"region_used">[] | null;
  readonly activityCategories: Tables<"activity_category_used">[] | null;
  readonly urlSearchParams: URLSearchParams;
}

export const SearchProvider = ({
  children,
  order: initialOrder,
  pagination,
  regions,
  activityCategories,
  urlSearchParams,
}: SearchProviderProps) => {
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
    values: valuesFromUrlSearchParams,
  });

  const {
    search: { data: searchResult },
    searchParams,
  } = useSearch(search);

  const ctx: SearchContextState = useMemo(
    () => ({
      search,
      dispatch,
      searchResult,
      searchParams,
      regions: regions ?? [],
      activityCategories: activityCategories ?? [],
    }),
    [search, searchResult, searchParams, regions, activityCategories]
  );

  useUpdatedUrlSearchParams(ctx);

  return (
    <SearchContext.Provider value={ctx}>{children}</SearchContext.Provider>
  );
};
