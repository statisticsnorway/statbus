"use client";
import { Input } from "@/components/ui/input";
import { useSearch } from "@/atoms/hooks"; // Changed to Jotai hook
import { useCallback } from "react";
import { useBaseData } from "@/atoms/hooks";
// import { externalIdentDeriveStateUpdateFromValues } from "./url-search-params"; // Removed

export default function ExternalIdentFilter() {
  const { externalIdentTypes } = useBaseData();
  const maybeDefaultExternalIdentType = externalIdentTypes?.[0];
  const { searchState, updateFilters, executeSearch } = useSearch();
  const currentValue = maybeDefaultExternalIdentType ? (searchState.filters[maybeDefaultExternalIdentType.code!] as string | undefined) ?? "" : "";

  const update = useCallback(
    async (app_param_value: string) => {
      if (maybeDefaultExternalIdentType) {
        const newFilters = { ...searchState.filters };
        if (app_param_value && app_param_value.trim() !== '') {
          newFilters[maybeDefaultExternalIdentType.code!] = app_param_value;
        } else {
          delete newFilters[maybeDefaultExternalIdentType.code!];
        }
        updateFilters(newFilters);
        await executeSearch();
      }
    },
    [searchState.filters, updateFilters, executeSearch, maybeDefaultExternalIdentType]
  );

  return maybeDefaultExternalIdentType ? (
    <Input
      type="text"
      placeholder={`Find units by ${maybeDefaultExternalIdentType?.name || ''}`}
      className="h-9 w-full md:max-w-[200px]"
      id="external-ident-search"
      name="external-ident-search"
      value={currentValue}
      onChange={(e) => update(e.target.value)}
    />
  ) : null;
}
