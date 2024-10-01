"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { LEGAL_FORM } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";

export default function LegalFormOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const {
    dispatch,
    search: {
      values: { [LEGAL_FORM]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const next = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      dispatch({
        type: "set_query",
        payload: {
          app_param_name: LEGAL_FORM,
          api_param_name: LEGAL_FORM,
          api_param_value: next.length ? `in.(${next.join(",")})` : null,
          app_param_values: next,
        },
      });
    },
    [dispatch, selected]
  );

  const reset = useCallback(() => {
    dispatch({
      type: "set_query",
      payload: {
        app_param_name: LEGAL_FORM,
        api_param_name: LEGAL_FORM,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [dispatch]);

  useEffect(() => {
    if (initialSelected.length > 0) {
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: LEGAL_FORM,
          api_param_name: LEGAL_FORM,
          api_param_value: `in.(${initialSelected.join(",")})`,
          app_param_values: initialSelected,
        },
      });
    }
  }, [dispatch, initialSelected]);

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
