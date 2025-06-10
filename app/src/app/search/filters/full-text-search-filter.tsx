"use client";
import { Input } from "@/components/ui/input";
import { useSearch } from "@/atoms/hooks"; // Changed to Jotai hook
import { useCallback, useEffect, useState } from "react";
// SEARCH and fullTextSearchDeriveStateUpdateFromValue are no longer needed

export default function FullTextSearchFilter() {
  const { searchState, updateSearchQuery, executeSearch } = useSearch();
  const [debouncedValue, setDebouncedValue] = useState<string>(searchState.query);

  // Synchronize local debouncedValue with global searchState.query if it changes externally
  useEffect(() => {
    setDebouncedValue(searchState.query);
  }, [searchState.query]);

  const update = useCallback(
    async (value: string) => {
      updateSearchQuery(value);
      await executeSearch();
    },
    [updateSearchQuery, executeSearch]
  );

  useEffect(() => {
    const handler = setTimeout(() => {
      update(debouncedValue);
    }, 300); // 300ms delay

    return () => {
      clearTimeout(handler);
    };
  }, [debouncedValue, update]);

  return (
    <Input
      type="text"
      placeholder="Find units by name"
      className="h-9 w-full md:max-w-[200px]"
      id="full-text-search"
      name="full-text-search"
      value={debouncedValue}
      onChange={(e) => setDebouncedValue(e.target.value)}
    />
  );
}
