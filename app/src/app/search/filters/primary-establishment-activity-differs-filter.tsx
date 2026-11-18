"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react";
import { PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS } from "@/app/search/filters/url-search-params";

// Data quality (xz3jej): shows that the list is narrowed to legal units whose primary
// establishment has another primary activity, and lets the user clear it. It appears only while
// the filter is on: the Data quality card on the dashboard is where it is switched on.
export default function PrimaryEstablishmentActivityDiffersFilter() {
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS];
  const selected = useMemo(
    () =>
      Array.isArray(filterValue) ? (filterValue as (string | null)[]) : [],
    [filterValue]
  );

  const reset = useCallback(() => {
    updateFilters({ ...filters, [PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS]: [] });
  }, [filters, updateFilters]);

  if (!selected.includes("true")) return null;

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Data quality"
      options={[
        {
          label: "Primary establishment has another activity",
          value: "true",
          humanReadableValue: "Other activity",
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={reset}
    />
  );
}
