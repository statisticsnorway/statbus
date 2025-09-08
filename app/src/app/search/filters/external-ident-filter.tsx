"use client";
import { Input } from "@/components/ui/input";
import { useSearchFilters } from "@/atoms/search";
import { externalIdentTypesAtom } from "@/atoms/base-data";
import { useAtomValue } from "jotai";
import { useCallback } from "react";

export default function ExternalIdentFilter() {
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const maybeDefaultExternalIdentType = externalIdentTypes?.[0];
  const { filters, updateFilters } = useSearchFilters();
  const currentValue = maybeDefaultExternalIdentType ? (filters[maybeDefaultExternalIdentType.code!] as string | undefined) ?? "" : "";

  const update = useCallback(
    async (app_param_value: string) => {
      if (maybeDefaultExternalIdentType) {
        const newFilters = { ...filters };
        if (app_param_value && app_param_value.trim() !== '') {
          newFilters[maybeDefaultExternalIdentType.code!] = app_param_value;
        } else {
          delete newFilters[maybeDefaultExternalIdentType.code!];
        }
        updateFilters(newFilters);
      }
    },
    [filters, updateFilters, maybeDefaultExternalIdentType]
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
