"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { UNIT_TYPE } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../search";

import { IURLSearchParamsDict, toURLSearchParams } from "@/lib/url-search-params-dict";

export default function UnitTypeFilter({ initialUrlSearchParamsDict: initialUrlSearchParams }: IURLSearchParamsDict) {
  const urlSearchParams = toURLSearchParams(initialUrlSearchParams);

  const unitType = urlSearchParams.get(UNIT_TYPE);
  const {
    modifySearchState,
    searchState: {
      values: { [UNIT_TYPE]: selected = [] },
    },
  } = useSearchContext();

  const buildQuery = (values: (string | null)[]) => {
    return values.length ? `in.(${values.join(",")})` : null;
  };

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: UNIT_TYPE,
          api_param_name: UNIT_TYPE,
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
        app_param_name: UNIT_TYPE,
        api_param_name: UNIT_TYPE,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [modifySearchState]);

  useEffect(() => {
    if (unitType) {
      const initialSelected = unitType.split(",");
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: UNIT_TYPE,
          api_param_name: UNIT_TYPE,
          api_param_value: buildQuery(initialSelected),
          app_param_values: initialSelected,
        },
      });
    }
  }, [modifySearchState, unitType]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Unit Type"
      options={[
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100",
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100",
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100",
        },
      ]}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
