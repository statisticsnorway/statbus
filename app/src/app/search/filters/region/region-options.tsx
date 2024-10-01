"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { REGION } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function RegionOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const {
    dispatch,
    search: {
      values: { [REGION]: selected = [] },
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
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: REGION,
          api_param_name: REGION,
          api_param_value: buildQuery(initialSelected),
          app_param_values: initialSelected,
        },
      });
    }
  }, [dispatch, initialSelected]);

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value) ? [] : [value];
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: REGION,
          api_param_name: REGION,
          api_param_value: buildQuery(values),
          app_param_values: values,
        },
      });
    },
    [dispatch, selected]
  );

  const reset = useCallback(() => {
    dispatch({
      type: "set_query",
      payload: {
        app_param_name: REGION,
        api_param_name: REGION,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [dispatch]);

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
