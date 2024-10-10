"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect, useState } from "react";
import { SEARCH } from "@/app/search/filters/url-search-params";
import { generateFTSQuery } from "@/app/search/generate-fts-query";

import { IURLSearchParamsDict, toURLSearchParams } from "@/lib/url-search-params-dict";

export default function FullTextSearchFilter({ initialUrlSearchParamsDict: initialUrlSearchParams }: IURLSearchParamsDict) {
  const urlSearchParams = toURLSearchParams(initialUrlSearchParams);
  const searchValue = urlSearchParams.get(SEARCH);
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [SEARCH]: selected = [] },
    },
  } = useSearchContext();

  const [debouncedValue, setDebouncedValue] = useState<string>(selected[0] ?? "");

  const update = useCallback(
    (value: string) => {
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: SEARCH,
          api_param_name: SEARCH,
          api_param_value: value
            ? `fts(simple).${generateFTSQuery(value)}`
            : null,
          app_param_values: value ? [value] : [],
        },
      });
    },
    [modifySearchState]
  );

  useEffect(() => {
    const handler = setTimeout(() => {
      update(debouncedValue);
    }, 300); // 300ms delay

    return () => {
      clearTimeout(handler);
    };
  }, [debouncedValue, update]);

  useEffect(() => {
    if (searchValue) {
      update(searchValue);
    }
  }, [update, searchValue]);

  return (
    <Input
      type="text"
      placeholder="Find units by name"
      className="h-9 w-full md:max-w-[200px]"
      id="full-text-search"
      name="full-text-search"
      value={debouncedValue}
      onChange={(e) => setDebouncedValue(e.target.value)}
    />
  );
}
