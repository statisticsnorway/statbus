"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { generateFTSQuery } from "@/app/search/hooks/use-search";
import { useEffect, useState } from "react";
import { SEARCH } from "@/app/search/filtersV2/url-search-params";

interface IProps {
  value: string | null;
}

export default function FullTextSearchFilter({ value: initialValue }: IProps) {
  const { dispatch } = useSearchContext();
  const [value, setValue] = useState(initialValue ?? "");

  useEffect(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: SEARCH,
        query: value ? `fts.${generateFTSQuery(value)}` : null,
      },
    });
  }, [dispatch, value]);

  return (
    <Input
      type="text"
      placeholder="Find units by name"
      className="h-9 w-full md:max-w-[200px]"
      value={value}
      onChange={(e) => setValue(e.target.value)}
    />
  );
}
