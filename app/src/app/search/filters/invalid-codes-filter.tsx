"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { INVALID_CODES, invalidCodesDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";

export default function InvalidCodesFilter() {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [INVALID_CODES]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    ({ value }: { value: string | null }) => {
      modifySearchState(invalidCodesDeriveStateUpdateFromValues(value));
    },
    [modifySearchState]
  );

  const reset = useCallback(() => {
    modifySearchState(invalidCodesDeriveStateUpdateFromValues(null));
  }, [modifySearchState]);

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
