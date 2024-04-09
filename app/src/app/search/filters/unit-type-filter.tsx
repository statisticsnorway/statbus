"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { UNIT_TYPE } from "@/app/search/filters/url-search-params";

interface IProps {
  urlSearchParam: string | null;
}

export default function UnitTypeFilter({ urlSearchParam: param }: IProps) {
  const {
    dispatch,
    search: {
      values: { [UNIT_TYPE]: selected = param?.split(",") ?? ["enterprise"] },
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
          name: UNIT_TYPE,
          query: next.length ? `in.(${next.join(",")})` : null,
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
        name: UNIT_TYPE,
        query: null,
        values: [],
      },
    });
  }, [dispatch]);

  useEffect(() => {
    if (param) {
      const initialSelected = param.split(",");
      dispatch({
        type: "set_query",
        payload: {
          name: UNIT_TYPE,
          query: `in.(${initialSelected.join(",")})`,
          values: initialSelected,
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
