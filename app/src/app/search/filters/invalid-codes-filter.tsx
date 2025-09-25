"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react"; // Added useMemo
import { INVALID_CODES } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search.d";

export default function InvalidCodesFilter() {
  const { filters, updateFilters } = useSearchFilters();
  // const selected = (filters[INVALID_CODES] as string[]) || [];
  const filterValue = filters[INVALID_CODES];
  const selected = useMemo(() => {
    if (Array.isArray(filterValue)) {
      return filterValue as string[];
    }
    if (typeof filterValue === 'string') {
      return [filterValue];
    }
    return [];
  }, [filterValue]);

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
          ...filters,
          [INVALID_CODES]: [],
        };
        updateFilters(newFilters);
        return;
      }

      const newSelectedValues = selected.includes(valueToToggle) ? [] : [valueToToggle];
      const newFilters = {
        ...filters,
        [INVALID_CODES]: newSelectedValues,
      };
      updateFilters(newFilters);
    },
    [filters, updateFilters, selected]
  );

  const reset = useCallback(async () => {
    const newFilters = {
      ...filters,
      [INVALID_CODES]: [],
    };
    updateFilters(newFilters);
  }, [filters, updateFilters]);

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
