"use client";
import { useContext } from "react";
import { SearchContext } from "@/app/search/search-context";

export const useSearchContext = () => {
  const context = useContext(SearchContext);
  if (!context) {
    throw new Error("useSearchContext must be used within a SearchProvider");
  }
  return context;
};
