"use client";
import { Dispatch, ReactNode, useMemo, useReducer } from "react";
import { searchFilterReducer } from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/use-search";
import useUpdatedUrlSearchParams from "@/app/search/use-updated-url-search-params";
import { SearchContext } from "@/app/search/search-context";

export interface SearchContextState {
  readonly search: SearchState;
  readonly dispatch: Dispatch<SearchAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
}

interface SearchProviderProps {
  readonly children: ReactNode;
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
}

export const SearchProvider = ({
  children,
  order: initialOrder,
  pagination,
}: SearchProviderProps) => {
  const [search, dispatch] = useReducer(searchFilterReducer, {
    order: initialOrder,
    pagination,
    queries: {},
    values: {},
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
    }),
    [search, searchResult, searchParams]
  );

  useUpdatedUrlSearchParams(ctx);

  return (
    <SearchContext.Provider value={ctx}>{children}</SearchContext.Provider>
  );
};
