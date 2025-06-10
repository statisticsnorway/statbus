"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearch } from "@/atoms/hooks";
import { useCallback } from "react";
import { INVALID_CODES } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search";

export default function InvalidCodesFilter() {
  const { searchState, updateFilters, executeSearch } = useSearch();
  const selected = (searchState.filters[INVALID_CODES] as string[]) || [];

  const update = useCallback(
    async (option: SearchFilterOption) => {
      // For a single toggle option like "Import Issues: Yes",
      // toggling means either setting it to ["yes"] or clearing it to [].
      // If option.value is null, it implies an unexpected state or a "clear" action
      // not directly handled by toggling this specific option.
      // Given the filter only has "yes", we assume option.value will be "yes" if not null.
      const valueToToggle = option.value;
      if (valueToToggle === null) {
        // If value is null, it's not the "yes" option, so effectively clear the filter.
        // Or, if this scenario shouldn't happen, log an error.
        // For now, let's assume clearing is the intent if value is null.
        const newFilters = {
          ...searchState.filters,
          [INVALID_CODES]: [],
        };
        updateFilters(newFilters);
        await executeSearch();
        return;
      }

      const newSelectedValues = selected.includes(valueToToggle) ? [] : [valueToToggle];
      const newFilters = {
        ...searchState.filters,
        [INVALID_CODES]: newSelectedValues,
      };
      updateFilters(newFilters);
      await executeSearch();
    },
    [searchState.filters, updateFilters, executeSearch, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...searchState.filters,
      [INVALID_CODES]: [],
    };
    updateFilters(newFilters);
    await executeSearch();
  }, [searchState.filters, updateFilters, executeSearch]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Import Issues"
      options={[
        {
          label: "Yes",
          value: "yes",
          humanReadableValue: "Yes",
          className: "bg-orange-200",
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={update}
    />
  );
}
