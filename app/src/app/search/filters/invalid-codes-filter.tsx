"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { INVALID_CODES } from "@/app/search/filters/url-search-params";

export default function InvalidCodesFilter({ initialUrlSearchParams}: { initialUrlSearchParams: URLSearchParams }) {
  const invalidCodes = initialUrlSearchParams.get(INVALID_CODES);

  const {
    modifySearchState,
    searchState: {
      values: { [INVALID_CODES]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    ({ value }: { value: string | null }) => {
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: INVALID_CODES,
          api_param_name: INVALID_CODES,
          api_param_value: value === "yes" ? `not.is.null` : null,
          app_param_values: [value],
        },
      });
    },
    [modifySearchState]
  );

  const reset = useCallback(() => {
    modifySearchState({
      type: "set_query",
      payload: {
        app_param_name: INVALID_CODES,
        api_param_name: INVALID_CODES,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [modifySearchState]);

  useEffect(() => {
    if (invalidCodes) {
      update({ value: invalidCodes });
    }
  }, [update, invalidCodes]);

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
