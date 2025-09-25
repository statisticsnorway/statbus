"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; // Added useMemo
import { LEGAL_FORM } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";

export default function LegalFormOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[LEGAL_FORM];
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
        ...filters,
        [LEGAL_FORM]: toggledValue,
      };
      updateFilters(newFilters);
    },
    [filters, updateFilters, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [LEGAL_FORM]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);


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
