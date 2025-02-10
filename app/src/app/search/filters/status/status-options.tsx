"use client";

import { SearchFilterOption } from "../../search";
import { OptionsFilter } from "../../components/options-filter";
import { useCallback } from "react";
import { useSearchContext } from "../../use-search-context";
import {
  STATUS,
  statusDeriveStateUpdateFromValues,
} from "../url-search-params";

export default function StatusOptions({
  options,
}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [STATUS]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState(statusDeriveStateUpdateFromValues(values));
    },
    [selected, modifySearchState]
  );

  const reset = useCallback(() => {
    modifySearchState(statusDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Status"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
