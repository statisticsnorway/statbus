"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; // Added useMemo
import { SECTOR } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";

export default function SectorOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[SECTOR];
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
      // Assuming this filter behaves like a single-choice toggle (or clear)
      const newSelectedValues = selected.includes(value) ? [] : [value];
      const newFilters = {
        ...filters,
        [SECTOR]: newSelectedValues,
      };
      updateFilters(newFilters);
    },
    [filters, updateFilters, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [SECTOR]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

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
