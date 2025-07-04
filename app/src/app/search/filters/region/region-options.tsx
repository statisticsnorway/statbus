"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/search"; // Changed to Jotai hook
import { useCallback, useMemo } from "react"; // Added useMemo
import { REGION } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";

export default function RegionOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  // const selected = (searchState.filters[REGION] as (string | null)[]) || [];
  const filterValue = searchState.filters[REGION];
  const selected = useMemo(() => {
    if (Array.isArray(filterValue)) {
      return filterValue as (string | null)[];
    }
    if (typeof filterValue === 'string') {
      return [filterValue];
    }
    return [];
  }, [filterValue]);

  const toggle = useCallback(
    async ({ value }: SearchFilterOption) => {
      const toggledValues = selected.includes(value) ? [] : [value];
      const newFilters = {
        ...searchState.filters,
        [REGION]: toggledValues,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [searchState.filters, updateFilters, executeSearch, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [REGION]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Region"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
