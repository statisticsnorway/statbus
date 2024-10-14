"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { UNIT_TYPE, unitTypeDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search";

export default function UnitTypeFilter() {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [UNIT_TYPE]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState(unitTypeDeriveStateUpdateFromValues(values));
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState(unitTypeDeriveStateUpdateFromValues(selected));
  }, [modifySearchState, selected]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Unit Type"
      options={[
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100",
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100",
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100",
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
