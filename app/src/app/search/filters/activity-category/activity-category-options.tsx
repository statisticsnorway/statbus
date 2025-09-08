"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; // Added useMemo
import { ACTIVITY_CATEGORY_PATH } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";

export default function ActivityCategoryOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[ACTIVITY_CATEGORY_PATH];
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
        ...filters,
        [ACTIVITY_CATEGORY_PATH]: toggledValues,
      };
      updateFilters(newFilters);
    },
    [filters, updateFilters, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [ACTIVITY_CATEGORY_PATH]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Activity Category"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
