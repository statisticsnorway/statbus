"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { ACTIVITY_CATEGORY_PATH } from "@/app/search/filters/url-search-params";

export default function ActivityCategoryOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const {
    dispatch,
    search: {
      values: { [ACTIVITY_CATEGORY_PATH]: selected = initialSelected ?? [] },
    },
  } = useSearchContext();

  useEffect(() => {
    if (initialSelected.length > 0) {
      dispatch({
        type: "set_query",
        payload: {
          name: ACTIVITY_CATEGORY_PATH,
          query: `cd.${initialSelected[0]}`,
          values: initialSelected,
        },
      });
    }
  }, [dispatch, initialSelected]);

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const next = selected.includes(value) ? [] : [value];
      const path = next[0];
      dispatch({
        type: "set_query",
        payload: {
          name: ACTIVITY_CATEGORY_PATH,
          query: path ? `cd.${path}` : path === null ? "is.null" : null,
          values: next,
        },
      });
    },
    [dispatch, selected]
  );

  const reset = useCallback(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: ACTIVITY_CATEGORY_PATH,
        query: null,
        values: [],
      },
    });
  }, [dispatch]);

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
