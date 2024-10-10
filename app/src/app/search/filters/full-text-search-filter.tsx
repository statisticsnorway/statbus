"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { SEARCH } from "@/app/search/filters/url-search-params";
import { generateFTSQuery } from "@/app/search/generate-fts-query";

interface IProps {
  readonly initialUrlSearchParams: URLSearchParams;
}

export default function FullTextSearchFilter({ initialUrlSearchParams }: IProps) {
  const searchValue = initialUrlSearchParams.get(SEARCH);
  const {
    modifySearchState,
    searchState: {
      values: { [SEARCH]: selected = [] },
    },
  } = useSearchContext();

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
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  );
}
