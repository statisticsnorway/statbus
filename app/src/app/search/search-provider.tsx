import {createContext, Dispatch, ReactNode, useContext, useMemo, useReducer} from "react";
import {searchFilterReducer} from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/hooks/use-search";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {Tables} from "@/lib/database.types";

export interface SearchContextState {
  readonly search: SearchState;
  readonly dispatch: Dispatch<SearchAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

const SearchContext = createContext<SearchContextState | null>(null)

interface SearchProviderProps {
  readonly children: ReactNode;
  readonly filters: SearchFilter[];
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

export const SearchProvider = (
  {
    children,
    filters: initialFilters,
    order: initialOrder,
    pagination,
    regions,
    activityCategories
  }: SearchProviderProps) => {

  const [search, dispatch] = useReducer(searchFilterReducer, {
    filters: initialFilters,
    order: initialOrder,
    pagination
  })

  const {search: {data: searchResult}, searchParams} = useSearch(search)

  const ctx: SearchContextState = useMemo(() => ({
    search,
    dispatch,
    searchResult,
    searchParams,
    regions,
    activityCategories
  }), [search, searchResult, searchParams, regions, activityCategories])

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
