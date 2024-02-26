import {createContext, Dispatch, ReactNode, useContext, useReducer} from "react";
import {searchFilterReducer} from "@/app/search/hooks/use-filter";
import useSearch from "@/app/search/hooks/use-search";
import {SearchFilter, SearchResult} from "@/app/search/search.types";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {Tables} from "@/lib/database.types";

interface SearchContextState {
  readonly filters: SearchFilter[];
  readonly dispatch: Dispatch<any>;
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

export const SearchProvider = ({children, filters: initialFilters, regions, activityCategories}: SearchProviderProps) => {
  const [filters, dispatch] = useReducer(searchFilterReducer, initialFilters)
  const {search: {data: searchResult}, searchParams} = useSearch(filters)

  useUpdatedUrlSearchParams(filters)

  return (
    <SearchContext.Provider value={{filters, dispatch, searchResult, searchParams, regions, activityCategories}}>
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
