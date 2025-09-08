"use client";

import { SearchFilterOption } from "../../search.d";
import { OptionsFilter } from "../../components/options-filter";
import { useCallback, useMemo } from "react"; // Added useMemo
import { useSearchFilters } from "@/atoms/search";
import {
  STATUS,
} from "../url-search-params";

export default function StatusOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[STATUS];
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
      const newSelectedValues = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      const newFilters = {
        ...filters,
        [STATUS]: newSelectedValues,
      };
      updateFilters(newFilters);
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [STATUS]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

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
