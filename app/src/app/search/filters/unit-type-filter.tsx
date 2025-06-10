"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
// import { useSearchContext } from "@/app/search/use-search-context"; // Removed
import { useSearch } from "@/atoms/hooks"; // Using Jotai's useSearch
import { useCallback } from "react";
import { UNIT_TYPE, unitTypeDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params"; // This might need update
import { SearchFilterOption } from "../search";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export default function UnitTypeFilter() {
  const { searchState, updateFilters } = useSearch();
  // TODO: Adapt logic for selected values and updating filters
  // const selected = searchState.filters[UNIT_TYPE] || []; // Example adaptation
  const selected: (string | null)[] = (searchState.filters[UNIT_TYPE] as string[]) || [];


  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const currentValues = Array.isArray(searchState.filters[UNIT_TYPE]) ? searchState.filters[UNIT_TYPE] as string[] : [];
      const newValues = currentValues.includes(value as string)
        ? currentValues.filter((v) => v !== value)
        : [...currentValues, value as string];
      
      // updateFilters should be called with the entire filters object
      updateFilters({ ...searchState.filters, [UNIT_TYPE]: newValues });
    },
    [searchState.filters, updateFilters]
  );

  const reset = useCallback(() => {
    const newFilters = { ...searchState.filters };
    delete newFilters[UNIT_TYPE];
    updateFilters(newFilters);
  }, [searchState.filters, updateFilters]);

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
