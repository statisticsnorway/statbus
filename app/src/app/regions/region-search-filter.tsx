"use client";
import { useCallback, useEffect } from "react";
import { generateFTSQuery } from "../search/generate-fts-query";
import { useRegionContext } from "./use-region-context";
import { Input } from "@/components/ui/input";

export default function RegionSearchFilter({
  urlSearchParam,
  name,
}: {
  readonly urlSearchParam: string | null;
  readonly name: string;
}) {
  const {
    dispatch,
    regions: {
      values: { [name]: selected = [] },
    },
  } = useRegionContext();

  const update = useCallback(
    (value: string) => {
      dispatch({
        type: "set_query",
        payload: {
          name: name,
          query: value ? `fts(simple).${generateFTSQuery(value)}` : null,
          values: value ? [value] : [],
        },
      });
    },
    [dispatch]
  );
  useEffect(() => {
    if (urlSearchParam) {
      update(urlSearchParam);
    }
  }, [update, urlSearchParam]);
  return (
    <Input
      type="text"
      placeholder={`Find units by ${name}`}
      className="h-9 w-full md:max-w-[200px]"
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  );
}
