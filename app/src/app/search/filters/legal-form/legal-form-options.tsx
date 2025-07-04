"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/search"; // Changed to Jotai hook
import { useCallback, useMemo } from "react"; // Added useMemo
import { LEGAL_FORM } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";

export default function LegalFormOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const filterValue = searchState.filters[LEGAL_FORM];
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
      const toggledValue = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      const newFilters = {
        ...searchState.filters,
        [LEGAL_FORM]: toggledValue,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [searchState.filters, updateFilters, executeSearch, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [LEGAL_FORM]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);


  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Legal Form"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
