"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";
import { INVALID_CODES } from "@/app/search/filtersV2/url-search-params";

interface IProps {
  value: string | null;
}

export default function InvalidCodesFilter({ value: initial }: IProps) {
  const { dispatch } = useSearchContext();
  const [value, setValue] = useState<string | null>(initial);

  useEffect(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: INVALID_CODES,
        query: value === "yes" ? `not.is.null` : null,
      },
    });
  }, [dispatch, value]);

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
      selectedValues={[value]}
      onReset={() => setValue(null)}
      onToggle={({ value }) => {
        setValue(value);
      }}
    />
  );
}
