"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { SECTOR } from "@/app/search/filters/url-search-params";

export default function SectorOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const {
    dispatch,
    search: {
      values: { [SECTOR]: selected = [] },
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
          name: SECTOR,
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
        name: SECTOR,
        query: null,
        values: [],
      },
    });
  }, [dispatch]);

  useEffect(() => {
    if (initialSelected.length > 0) {
      dispatch({
        type: "set_query",
        payload: {
          name: SECTOR,
          query: `in.(${initialSelected.join(",")})`,
          values: initialSelected,
        },
      });
    }
  }, [dispatch, initialSelected]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Sector"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
