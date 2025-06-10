"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/hooks"; // Changed to Jotai hook
import { useCallback } from "react";
import { SECTOR } from "@/app/search/filters/url-search-params"; // Removed unused import
import { SearchFilterOption } from "../../search";

export default function SectorOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const selected = (searchState.filters[SECTOR] as (string | null)[]) || [];

  const toggle = useCallback(
    async ({ value }: SearchFilterOption) => {
      // Assuming this filter behaves like a single-choice toggle (or clear)
      const newSelectedValues = selected.includes(value) ? [] : [value];
      const newFilters = {
        ...searchState.filters,
        [SECTOR]: newSelectedValues,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [searchState.filters, updateFilters, executeSearch, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [SECTOR]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Sector"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
