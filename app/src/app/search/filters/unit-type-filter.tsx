"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/hooks"; // Using Jotai's useSearch
import { useCallback, useMemo } from "react"; // Added useMemo
import { UNIT_TYPE } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export default function UnitTypeFilter() {
  const { searchState, updateFilters, executeSearch } = useSearch(); // Added executeSearch
  const filterValue = searchState.filters[UNIT_TYPE];
  const selected = useMemo(() => {
    if (Array.isArray(filterValue)) {
      return filterValue as string[];
    }
    if (typeof filterValue === 'string') {
      return [filterValue];
    }
    return [];
  }, [filterValue]);


  const toggle = useCallback(
    async ({ value }: SearchFilterOption) => { // Made async
      const currentValues = selected; // Use the memoized selected value
      const newValues = currentValues.includes(value as string)
        ? currentValues.filter((v) => v !== value)
        : [...currentValues, value as string];
      
      updateFilters({ ...searchState.filters, [UNIT_TYPE]: newValues });
      await executeSearch(); // Added executeSearch
    },
    [selected, searchState.filters, updateFilters, executeSearch] // Added executeSearch to deps
  );

  const reset = useCallback(async () => { // Made async
    const newFilters = { ...searchState.filters };
    delete newFilters[UNIT_TYPE]; // Or set to [] if that's preferred for consistency
    updateFilters(newFilters);
    await executeSearch(); // Added executeSearch
  }, [searchState.filters, updateFilters, executeSearch]); // Added executeSearch to deps

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Unit Type"
      options={[
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100",
          icon: <StatisticalUnitIcon type="enterprise" className="w-4" />,
        },
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100",
          icon: <StatisticalUnitIcon type="legal_unit" className="w-4" />,
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100",
          icon: <StatisticalUnitIcon type="establishment" className="w-4" />,
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
