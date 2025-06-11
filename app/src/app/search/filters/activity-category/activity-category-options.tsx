"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/hooks";
import { useCallback, useMemo } from "react"; // Added useMemo
import { ACTIVITY_CATEGORY_PATH } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function ActivityCategoryOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const filterValue = searchState.filters[ACTIVITY_CATEGORY_PATH];
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
        [ACTIVITY_CATEGORY_PATH]: toggledValues,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [searchState.filters, updateFilters, executeSearch, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [ACTIVITY_CATEGORY_PATH]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);

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
