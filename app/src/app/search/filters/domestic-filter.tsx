"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; 
import { DOMESTIC } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search.d";


export default function DomesticFilter() {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[DOMESTIC];
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
        [DOMESTIC]: toggledValues,
      };
      updateFilters(newFilters);
    },
    [selected, filters, updateFilters] 
  );



  const reset = useCallback(async () => { 
    const newFilters = { ...filters, [DOMESTIC]: [] };
    updateFilters(newFilters);
  }, [filters, updateFilters]); 

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Domestic"
      options={[
        {
          label: "Yes",
          value: "true",
          humanReadableValue: "Yes",
        },
        {
          label: "No",
          value: "false",
          humanReadableValue: "No",
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
