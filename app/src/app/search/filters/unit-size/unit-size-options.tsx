"use client";

import { SearchFilterOption } from "../../search";
import { OptionsFilter } from "../../components/options-filter";
import { useCallback } from "react";
import { useSearchContext } from "../../use-search-context";
import {
  UNIT_SIZE,
  unitSizeDeriveStateUpdateFromValues,
} from "../url-search-params";

export default function UnitSizeOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [UNIT_SIZE]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState(unitSizeDeriveStateUpdateFromValues(values));
    },
    [selected, modifySearchState]
  );

  const reset = useCallback(() => {
    modifySearchState(unitSizeDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Unit Size"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
