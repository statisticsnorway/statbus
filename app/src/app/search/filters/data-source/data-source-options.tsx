"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; // Added useMemo
import { DATA_SOURCE } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search.d";
import { Tables } from "@/lib/database.types";


export default function DataSourceOptions({
  options,
  dataSources,
}: {
  readonly options: SearchFilterOption[];
  readonly dataSources: Tables<"data_source_used">[];
}) {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[DATA_SOURCE];
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
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      const newFilters = {
        ...filters,
        [DATA_SOURCE]: values,
      };
      updateFilters(newFilters);
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [DATA_SOURCE]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Data Source"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
