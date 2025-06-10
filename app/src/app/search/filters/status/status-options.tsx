"use client";

import { SearchFilterOption } from "../../search";
import { OptionsFilter } from "../../components/options-filter";
import { useCallback } from "react";
import { useSearch } from "@/atoms/hooks"; // Changed to Jotai hook
import {
  STATUS,
  // statusDeriveStateUpdateFromValues, // Removed
} from "../url-search-params";

export default function StatusOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const selected = (searchState.filters[STATUS] as (string | null)[]) || [];

  const toggle = useCallback(
    async ({ value }: SearchFilterOption) => {
      const newSelectedValues = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      const newFilters = {
        ...searchState.filters,
        [STATUS]: newSelectedValues,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [selected, searchState.filters, updateFilters, executeSearch]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [STATUS]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Status"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
