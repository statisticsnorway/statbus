"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { LEGAL_FORM, legalFormDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function LegalFormOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [LEGAL_FORM]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const toggledValue = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState(legalFormDeriveStateUpdateFromValues(toggledValue));
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState(legalFormDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);


  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Legal Form"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
