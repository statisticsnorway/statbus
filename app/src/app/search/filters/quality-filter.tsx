"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react";
import {
  QUALITY,
  QUALITY_CHECKS,
  isQualityCheck,
} from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search.d";

// Quality (xz3jej): narrows the list to the units one quality check lists (quality=<check>), and
// lets the user switch check or clear it. It appears only while a check is chosen: the dashboard's
// Data quality cards are where a check is opened from.
export default function QualityFilter() {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[QUALITY];
  const selected = useMemo(() => {
    const values = Array.isArray(filterValue)
      ? (filterValue as (string | null)[])
      : [];
    return values.filter((value) => isQualityCheck(value));
  }, [filterValue]);

  const options = useMemo<SearchFilterOption[]>(
    () =>
      Object.entries(QUALITY_CHECKS).map(([check, { label, shortLabel }]) => ({
        label,
        value: check,
        humanReadableValue: shortLabel,
      })),
    []
  );

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const next =
        isQualityCheck(value) && !selected.includes(value) ? [value] : [];
      updateFilters({ ...filters, [QUALITY]: next });
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(() => {
    updateFilters({ ...filters, [QUALITY]: [] });
  }, [filters, updateFilters]);

  if (selected.length === 0) return null;

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Quality"
      options={options}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
