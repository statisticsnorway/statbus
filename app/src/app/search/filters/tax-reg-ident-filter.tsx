"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { TAX_REG_IDENT } from "@/app/search/filters/url-search-params";

interface IProps {
  urlSearchParam: string | null;
}

export default function TaxRegIdentFilter({ urlSearchParam }: IProps) {
  const {
    dispatch,
    search: {
      values: { [TAX_REG_IDENT]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    (value: string) => {
      dispatch({
        type: "set_query",
        payload: {
          name: TAX_REG_IDENT,
          query: value ? `eq.${value}` : null,
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
      placeholder="Find units by Tax Reg ID"
      className="h-9 w-full md:max-w-[200px]"
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  );
}
