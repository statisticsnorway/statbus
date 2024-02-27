import {createContext, Dispatch, ReactNode, useContext, useReducer} from "react";
import {searchFilterReducer} from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/hooks/use-search";
import {SearchFilter, SearchFilterAction, SearchOrder, SearchResult, SetOrderAction} from "@/app/search/search.types";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {Tables} from "@/lib/database.types";
import {searchOrderReducer} from "@/app/search/search-order-reducer";

interface SearchContextState {
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
  readonly filters: SearchFilter[];
  readonly order: SearchOrder;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

export const SearchProvider = (
  {
    children,
    filters: initialSearchFilters,
    order: initialSearchOrder,
    regions,
    activityCategories
  }: SearchProviderProps) => {

  const [searchFilters, searchFilterDispatch] = useReducer(searchFilterReducer, initialSearchFilters)
  const [searchOrder, searchOrderDispatch] = useReducer(searchOrderReducer, initialSearchOrder)
  const {search: {data: searchResult}, searchParams} = useSearch(searchFilters, searchOrder)

  useUpdatedUrlSearchParams(searchFilters, searchOrder)

  return (
    <SearchContext.Provider value={{
      searchFilters,
      searchFilterDispatch,
      searchOrder,
      searchOrderDispatch,
      searchResult,
      searchParams,
      regions,
      activityCategories
    }}>
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
