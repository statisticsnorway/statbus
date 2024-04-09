"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";
import { TAX_REG_IDENT } from "@/app/search/filtersV2/url-search-params";

interface IProps {
  urlSearchParam: string | null;
}

export default function TaxRegIdentFilter({ urlSearchParam: param }: IProps) {
  const { dispatch } = useSearchContext();
  const [value, setValue] = useState(param ?? "");

  useEffect(() => {
    dispatch({
      type: "set_query",
      payload: {
        name: TAX_REG_IDENT,
        query: value ? `eq.${value}` : null,
        urlValue: value || null,
      },
    });
  }, [dispatch, value]);

  return (
    <Input
      type="text"
      placeholder="Find units by Tax Reg ID"
      className="h-9 w-full md:max-w-[200px]"
      value={value}
      onChange={(e) => setValue(e.target.value)}
    />
  );
}
