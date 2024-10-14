"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { REGION, regionDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function RegionOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [REGION]: selected = [] },
    },
  } = useSearchContext();


  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const toggledValues = selected.includes(value) ? [] : [value];
      modifySearchState(regionDeriveStateUpdateFromValues(toggledValues));
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState(regionDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Region"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
