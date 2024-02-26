import {createContext, Dispatch, ReactNode, useContext, useReducer} from "react";
import {searchFilterReducer} from "@/app/search/search-filter-reducer";
import useSearch from "@/app/search/hooks/use-search";
import {SearchFilter, SearchFilterAction, SearchOrder, SearchResult, SetOrderAction} from "@/app/search/search.types";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {Tables} from "@/lib/database.types";
import {searchOrderReducer} from "@/app/search/search-order-reducer";

interface SearchContextState {
  readonly filters: SearchFilter[];
  readonly dispatch: Dispatch<SearchFilterAction>;
  readonly order: SearchOrder;
  readonly searchOrderDispatch: Dispatch<SetOrderAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

export const SearchContext = createContext<SearchContextState | null>(null)

interface SearchProviderProps {
  readonly children: ReactNode;
  readonly filters: SearchFilter[];
  readonly regions: Tables<'region_used'>[]
  readonly activityCategories: Tables<'activity_category_available'>[]
}

export const SearchProvider = (
  {
    children,
    filters: initialFilters,
    regions,
    activityCategories
  }: SearchProviderProps) => {

  const [filters, dispatch] = useReducer(searchFilterReducer, initialFilters)
  const [order, searchOrderDispatch] = useReducer(searchOrderReducer, {name: 'name', direction: 'asc'})
  const {search: {data: searchResult}, searchParams} = useSearch(filters, order)

  useUpdatedUrlSearchParams(filters)

  return (
    <SearchContext.Provider
      value={{
        filters,
        dispatch,
        searchResult,
        searchParams,
        order,
        searchOrderDispatch,
        regions,
        activityCategories,
      }}
    >
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
