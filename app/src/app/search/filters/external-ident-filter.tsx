"use client";
import { Input } from "@/components/ui/input";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { useBaseData } from "@/app/BaseDataClient";
import { externalIdentDeriveStateUpdateFromValues } from "./url-search-params";

export default function ExternalIdentFilter() {
  const { externalIdentTypes } = useBaseData();
  const maybeDefaultExternalIdentType = externalIdentTypes?.[0];
  const { modifySearchState, searchState } = useSearchContext();
  const selected = maybeDefaultExternalIdentType ? searchState.appSearchParams[maybeDefaultExternalIdentType.code!] ?? [] : [];

  const update = useCallback(
    (app_param_value: string) => {
      if (maybeDefaultExternalIdentType) {
        modifySearchState(
          externalIdentDeriveStateUpdateFromValues(maybeDefaultExternalIdentType, app_param_value)
          );
      }
    },
    [modifySearchState, maybeDefaultExternalIdentType]
  );

  return maybeDefaultExternalIdentType ? (
    <Input
      type="text"
      placeholder={`Find units by ${maybeDefaultExternalIdentType?.name || ''}`}
      className="h-9 w-full md:max-w-[200px]"
      id="external-ident-search"
      name="external-ident-search"
      value={selected[0] ?? ""}
      onChange={(e) => update(e.target.value)}
    />
  ) : null;
}
