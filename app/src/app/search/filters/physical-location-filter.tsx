"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react";
import { PHYSICAL_LOCATION } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search.d";

// Physical Location: whether a unit has a physical location ("present") or not
// ("missing"); see PHYSICAL_LOCATION in url-search-params.ts. Shown so a search
// that narrows on it, such as the Units Missing Physical Location card's,
// says so and can be cleared.
export default function PhysicalLocationFilter() {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[PHYSICAL_LOCATION];
  const selected = useMemo(() => {
    if (Array.isArray(filterValue)) return filterValue as (string | null)[];
    if (typeof filterValue === "string") return [filterValue];
    return [];
  }, [filterValue]);

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      updateFilters({
        ...filters,
        [PHYSICAL_LOCATION]: selected.includes(value) ? [] : [value],
      });
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(() => {
    updateFilters({ ...filters, [PHYSICAL_LOCATION]: [] });
  }, [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Physical Location"
      options={[
        { label: "Present", value: "present", humanReadableValue: "Present" },
        { label: "Missing", value: "missing", humanReadableValue: "Missing" },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
