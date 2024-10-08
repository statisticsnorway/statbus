"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useEffect } from "react";
import { useBaseData } from "@/app/BaseDataClient";

export default function ExternalIdentFilter({ urlSearchParams }: { urlSearchParams: URLSearchParams }) {
  const { externalIdentTypes } = useBaseData();
  const maybeDefaultExternalIdent = externalIdentTypes?.[0];
  const maybeDefaultCode = maybeDefaultExternalIdent?.code;
  const urlSearchParam = maybeDefaultCode ? new URLSearchParams(urlSearchParams).get(maybeDefaultCode) : null;
  const { dispatch, search } = useSearchContext();
  const selected = maybeDefaultCode ? search.values[maybeDefaultCode] ?? [] : [];

  const update = useCallback(
    (app_param_value: string) => {
      if (maybeDefaultCode) {
        dispatch({
          type: "set_query",
          payload: {
            app_param_name: maybeDefaultCode,
            api_param_name: `external_idents->>${maybeDefaultCode}`,
            api_param_value: app_param_value ? `eq.${app_param_value}` : null,
            app_param_values: app_param_value ? [app_param_value] : [],
          },
        });
      }
    },
    [dispatch, maybeDefaultCode]
  );

  useEffect(() => {
    if (urlSearchParam) {
      update(urlSearchParam);
    }
  }, [update, urlSearchParam]);

  return maybeDefaultCode ? (
    <Input
      type="text"
      placeholder={`Find units by ${maybeDefaultExternalIdent?.name || ''}`}
      className="h-9 w-full md:max-w-[200px]"
      id="external-ident-search"
      name="external-ident-search"
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  ) : null;
}
