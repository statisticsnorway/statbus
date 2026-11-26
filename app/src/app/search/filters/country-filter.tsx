"use client";
import { useCallback, useMemo } from "react";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters, useSearchPageData } from "@/atoms/search";
import { PHYSICAL_COUNTRY } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search.d";

/**
 * The countries units are located in (z2qt08), from country_used: only countries that have
 * units. The toolbar shows it with the Country column, and always while it narrows the search
 * (FilterWrapper), so the Regions map's "View and download" for a foreign country lands on a
 * list that names the country.
 */
export default function CountryFilter() {
  const { allCountries } = useSearchPageData();
  const { filters, updateFilters } = useSearchFilters();
  const filterValue = filters[PHYSICAL_COUNTRY];
  const selected = useMemo(
    () => (Array.isArray(filterValue) ? (filterValue as (string | null)[]) : typeof filterValue === "string" ? [filterValue] : []),
    [filterValue]
  );
  const options = useMemo(
    () =>
      (allCountries ?? [])
        .filter((c) => c.id != null)
        .map(({ id, iso_2, name }) => ({ label: `${name} (${iso_2})`, value: String(id), humanReadableValue: name ?? String(id) })),
    [allCountries]
  );

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value];
      updateFilters({ ...filters, [PHYSICAL_COUNTRY]: next });
    },
    [selected, filters, updateFilters]
  );
  const reset = useCallback(() => updateFilters({ ...filters, [PHYSICAL_COUNTRY]: [] }), [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Country"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
