"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { ACTIVITY_CATEGORY_PATH } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function ActivityCategoryOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [ACTIVITY_CATEGORY_PATH]: selected = [] },
    },
  } = useSearchContext();

  const buildQuery = (values: (string | null)[]) => {
    const path = values[0];
    if (path) return `cd.${path}`;
    if (path === null) return "is.null";
    return null;
  };

  useEffect(() => {
    if (initialSelected.length > 0) {
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: ACTIVITY_CATEGORY_PATH,
          api_param_name: ACTIVITY_CATEGORY_PATH,
          api_param_value: buildQuery(initialSelected),
          app_param_values: initialSelected,
        },
      });
    }
  }, [modifySearchState, initialSelected]);

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value) ? [] : [value];
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: ACTIVITY_CATEGORY_PATH,
          api_param_name: ACTIVITY_CATEGORY_PATH,
          api_param_value: buildQuery(values),
          app_param_values: values,
        },
      });
    },
    [modifySearchState, selected]
  );

  const reset = useCallback(() => {
    modifySearchState({
      type: "set_query",
      payload: {
        app_param_name: ACTIVITY_CATEGORY_PATH,
        api_param_name: ACTIVITY_CATEGORY_PATH,
        api_param_value: null,
        app_param_values: [],
      },
    });
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
