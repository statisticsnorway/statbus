"use client";
import { createContext, Dispatch } from "react";

export interface SearchContextState {
  readonly search: SearchState;
  readonly dispatch: Dispatch<SearchAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
  // readonly regions: Tables<"region_used">[];
  // readonly activityCategories: Tables<"activity_category_available">[];
}

export const SearchContext = createContext<SearchContextState | null>(null);
