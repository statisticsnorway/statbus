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
  const defaultExternalIdent = externalIdentTypes?.[0];
  const defaultCode = defaultExternalIdent?.code;
  const urlSearchParam = new URLSearchParams(urlSearchParams).get(
    defaultCode
  );
  const {
    dispatch,
    search: {
      values: { [defaultCode]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback(
    (app_param_value: string) => {
      dispatch({
        type: "set_query",
        payload: {
          app_param_name: defaultCode,
          api_param_name: `external_idents->>${defaultCode}`,
          api_param_value: app_param_value ? `eq.${app_param_value}` : null,
          app_param_values: app_param_value ? [app_param_value] : [],
        },
      });
    },
    [dispatch, defaultCode]
  );

  useEffect(() => {
    if (urlSearchParam) {
      update(urlSearchParam);
    }
  }, [update, urlSearchParam]);

  return (
    <Input
      type="text"
      placeholder={`Find units by ${defaultExternalIdent?.name || ''}`}
      className="h-9 w-full md:max-w-[200px]"
      id="external-ident-search"
      name="external-ident-search"
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  );
}
