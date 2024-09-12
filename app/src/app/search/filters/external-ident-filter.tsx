"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

interface IProps {
  readonly urlSearchParams: URLSearchParams;
}

export default function ExternalIdentFilter({ urlSearchParams }: IProps) {
  const { externalIdentTypes } = useCustomConfigContext();
  const externalIdentType = externalIdentTypes?.[0]?.code;
  const urlSearchParam = new URLSearchParams(urlSearchParams).get(
    externalIdentType
  );
  const {
    dispatch,
    search: {
      values: { [externalIdentType]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    (app_param_value: string) => {
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: externalIdentType,
          api_param_name: `external_idents->>${externalIdentType}`,
          api_param_value: app_param_value ? `eq.${app_param_value}` : null,
          app_param_values: app_param_value ? [app_param_value] : [],
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
