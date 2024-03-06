import {createContext, Dispatch, ReactNode, useCallback, useContext, useMemo, useReducer, useState} from "react";
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
  readonly selected: Tables<"statistical_unit">[]
  readonly clearSelected: () => void
  readonly toggle: (unit: Tables<"statistical_unit">) => void
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
    filters: initialFilters,
    order: initialOrder,
    regions,
    activityCategories
  }: SearchProviderProps) => {

  const [search, dispatch] = useReducer(searchFilterReducer, {
    filters: initialFilters,
    order: initialOrder
  })

  const [selected, setSelected] = useState<Tables<"statistical_unit">[]>([])
  const toggle = useCallback((unit: Tables<"statistical_unit">) => {
    setSelected(prev => {
      const existing = prev.find(s => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type);
      return existing ? prev.filter(s => s !== existing) : [...prev, unit]
    })
  }, [setSelected])

  const {search: {data: searchResult}, searchParams} = useSearch(search)

  const ctx: SearchContextState = useMemo(() => ({
    search,
    dispatch,
    searchResult,
    searchParams,
    regions,
    activityCategories,
    selected,
    toggle,
    clearSelected: () => setSelected([])
  }), [toggle, selected, search, searchResult, searchParams, regions, activityCategories])

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
