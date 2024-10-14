"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect, useState } from "react";
import { SEARCH, fullTextSearchDeriveStateUpdateFromValue } from "@/app/search/filters/url-search-params";

export default function FullTextSearchFilter() {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [SEARCH]: selected = [] },
    },
  } = useSearchContext();

  const [debouncedValue, setDebouncedValue] = useState<string>(selected[0] ?? '');

  const update = useCallback(
    (value: string) => {
      modifySearchState(fullTextSearchDeriveStateUpdateFromValue(value));
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
