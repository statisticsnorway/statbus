"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { INVALID_CODES } from "@/app/search/filters/url-search-params";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default function InvalidCodesFilter({ urlSearchParam }: IProps) {
  const {
    dispatch,
    search: {
      values: { [INVALID_CODES]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    ({ value }: { value: string | null }) => {
      dispatch({
        type: "set_query",
        payload: {
          name: INVALID_CODES,
          query: value === "yes" ? `not.is.null` : null,
          values: [value],
        },
      });
    },
    [dispatch]
  );

  const reset = useCallback(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: INVALID_CODES,
        query: null,
        values: [],
      },
    });
  }, [dispatch]);

  useEffect(() => {
    if (urlSearchParam) {
      update({ value: urlSearchParam });
    }
  }, [update, urlSearchParam]);

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
