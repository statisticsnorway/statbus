"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { ACTIVITY_CATEGORY_PATH, activityCategoryDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function ActivityCategoryOptions({options}: {
  readonly options: SearchFilterOption[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [ACTIVITY_CATEGORY_PATH]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const toggledValues = selected.includes(value) ? [] : [value];
      modifySearchState(activityCategoryDeriveStateUpdateFromValues(toggledValues));
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState(activityCategoryDeriveStateUpdateFromValues([]));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Activity Category"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
