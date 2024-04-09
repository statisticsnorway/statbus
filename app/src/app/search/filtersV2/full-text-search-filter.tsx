"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";
import { SEARCH } from "@/app/search/filtersV2/url-search-params";
import { generateFTSQuery } from "@/app/search/generate-fts-query";

interface IProps {
  urlSearchParam: string | null;
}

export default function FullTextSearchFilter({
  urlSearchParam: param,
}: IProps) {
  const { dispatch } = useSearchContext();
  const [value, setValue] = useState(param ?? "");

  useEffect(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: SEARCH,
        query: value ? `fts(simple).${generateFTSQuery(value)}` : null,
        urlValue: value || null,
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
