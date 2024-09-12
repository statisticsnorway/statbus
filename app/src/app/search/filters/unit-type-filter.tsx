"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { UNIT_TYPE } from "@/app/search/filters/url-search-params";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default function UnitTypeFilter({ urlSearchParam: param }: IProps) {
  const {
    dispatch,
    search: {
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

      dispatch({
        type: "set_query",
        payload: {
          app_param_name: UNIT_TYPE,
          api_param_name: UNIT_TYPE,
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
        app_param_name: UNIT_TYPE,
        api_param_name: UNIT_TYPE,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [dispatch]);

  useEffect(() => {
    if (param) {
      const initialSelected = param.split(",");
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: UNIT_TYPE,
          api_param_name: UNIT_TYPE,
          api_param_value: buildQuery(initialSelected),
          app_param_values: initialSelected,
        },
      });
    }
  }, [dispatch, param]);

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
