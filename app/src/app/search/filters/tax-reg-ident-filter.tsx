"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default function TaxRegIdentFilter({ urlSearchParam }: IProps) {
  const { externalIdentTypes } = useCustomConfigContext();
  const externalIdentType = externalIdentTypes?.[0]?.code;
  const {
    dispatch,
    search: {
      values: { [`external_idents->>${externalIdentType}`]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    (value: string) => {
      dispatch({
        type: "set_query",
        payload: {
          name: `external_idents->>${externalIdentType}`,
          query: value ? `eq.${value}` : null,
          values: value ? [value] : [],
        },
      });
    },
    [dispatch, externalIdentType]
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
