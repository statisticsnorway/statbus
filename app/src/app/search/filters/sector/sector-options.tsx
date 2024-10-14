"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { SECTOR, sectorDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function SectorOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [SECTOR]: selected = [] },
    },
  } = useSearchContext();
  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value) ? [] : [value];
      modifySearchState(sectorDeriveStateUpdateFromValues(values));
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState(sectorDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Sector"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
