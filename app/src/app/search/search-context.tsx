"use client";
import { createContext, Dispatch } from "react";
import type { Tables } from "@/lib/database.types";

export interface SearchContextState {
  readonly search: SearchState;
  readonly dispatch: Dispatch<SearchAction>;
  readonly searchResult?: SearchResult;
  readonly searchParams: URLSearchParams;
  readonly regions: Tables<"region_used">[];
  readonly activityCategories: Tables<"activity_category_available">[];
  /**
   * Indicates whether the search is currently loading new data.
   */
  readonly isLoading: boolean;
}

export const SearchContext = createContext<SearchContextState | null>(null);
