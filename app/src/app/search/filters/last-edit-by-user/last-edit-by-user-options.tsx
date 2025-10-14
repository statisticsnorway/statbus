"use client";

import { SearchFilterOption } from "../../search.d";
import { OptionsFilter } from "../../components/options-filter";
import { useCallback, useMemo } from "react";
import { useSearchFilters } from "@/atoms/search";
import { LAST_EDIT_BY_USER } from "../url-search-params";

export default function LastEditByUserOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[LAST_EDIT_BY_USER];
  const selected = useMemo(() => {
    if (Array.isArray(filterValue)) {
      return filterValue as (string | null)[];
    }
    if (typeof filterValue === "string") {
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
        [LAST_EDIT_BY_USER]: newSelectedValues,
      };
      updateFilters(newFilters);
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [LAST_EDIT_BY_USER]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Last Edit By"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
