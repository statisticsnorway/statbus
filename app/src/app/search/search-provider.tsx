import {createContext, Dispatch, ReactNode, useContext, useMemo, useReducer} from "react";
import {searchFilterReducer} from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/hooks/use-search";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {Tables} from "@/lib/database.types";
import {searchOrderReducer} from "@/app/search/search-order-reducer";

export interface SearchContextState {
  readonly searchFilters: SearchFilter[];
  readonly searchFilterDispatch: Dispatch<SearchFilterAction>;
  readonly searchOrder: SearchOrder;
  readonly searchOrderDispatch: Dispatch<SetOrderAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

const SearchContext = createContext<SearchContextState | null>(null)

interface SearchProviderProps {
  readonly children: ReactNode;
  readonly searchFilters: SearchFilter[];
  readonly searchOrder: SearchOrder;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

export const SearchProvider = (
  {
    children,
    searchFilters: initialSearchFilters,
    searchOrder: initialSearchOrder,
    regions,
    activityCategories
  }: SearchProviderProps) => {

  const [searchFilters, searchFilterDispatch] = useReducer(searchFilterReducer, initialSearchFilters)
  const [searchOrder, searchOrderDispatch] = useReducer(searchOrderReducer, initialSearchOrder)
  const {search: {data: searchResult}, searchParams} = useSearch(searchFilters, searchOrder)

  const ctx = useMemo(() => ({
    searchFilters,
    searchFilterDispatch,
    searchOrder,
    searchOrderDispatch,
    searchResult,
    searchParams,
    regions,
    activityCategories
  }), [searchFilters, searchOrder, searchResult, searchParams, regions, activityCategories])

  useUpdatedUrlSearchParams(ctx)

  return (
    <SearchContext.Provider value={ctx}>
      {children}
    </SearchContext.Provider>
  )
}

export const useSearchContext = () => {
  const context = useContext(SearchContext)
  if (!context) {
    throw new Error('useSearchContext must be used within a SearchProvider')
  }
  return context
}
