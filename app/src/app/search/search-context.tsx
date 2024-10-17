"use client";
import { createContext, Dispatch } from "react";
import type { Tables } from "@/lib/database.types";
import { SearchAction, SearchResult, SearchState } from "./search";
import { TimeContextRow } from "../types";

export interface SearchContextState {
  readonly searchState: SearchState;
  readonly modifySearchState: Dispatch<SearchAction>;
  readonly searchResult?: SearchResult;
  readonly derivedApiSearchParams: URLSearchParams;
  readonly regions: Tables<"region_used">[];
  readonly activityCategories: Tables<"activity_category_available">[];
  readonly selectedTimeContext: TimeContextRow;
  /**
   * Indicates whether the search is currently loading new data.
   */
  readonly isLoading: boolean;
  readonly error?: Error;

}

export const SearchContext = createContext<SearchContextState | null>(null);
