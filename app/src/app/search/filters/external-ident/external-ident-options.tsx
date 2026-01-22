"use client";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { Tables } from "@/lib/database.types";
import { ConditionalValue } from "@/app/search/search";

export default function ExternalIdentOptions({ externalIdentType }: {
  readonly externalIdentType: Tables<"external_ident_type_ordered">;
}) {
  const { filters, updateFilters } = useSearchFilters();
  const currentFilterValue = filters[externalIdentType.code!] as string | undefined;

  const update = useCallback(async (value: ConditionalValue | null) => {
    const newFilters = { ...filters };
    if (value) {
      // External idents only support single eq condition, so extract the operand
      const operand = 'conditions' in value 
        ? value.conditions[0]?.operand 
        : value.operand;
      
      if (operand && operand.trim() !== '') {
        newFilters[externalIdentType.code!] = operand;
      } else {
        delete newFilters[externalIdentType.code!];
      }
    } else {
      delete newFilters[externalIdentType.code!];
    }
    updateFilters(newFilters);
  }, [filters, updateFilters, externalIdentType.code]);

  const reset = useCallback(async () => {
    const newFilters = { ...filters };
    delete newFilters[externalIdentType.code!];
    updateFilters(newFilters);
  }, [filters, updateFilters, externalIdentType.code]);

  const selected_value = useMemo(() => 
    currentFilterValue && currentFilterValue.length > 0 
      ? { operator: "eq" as const, operand: currentFilterValue } 
      : null
  , [currentFilterValue]);

  return (
    <ConditionalFilter
      className="p-2 h-9"
      title={externalIdentType.name!}
      selected={selected_value}
      onChange={update}
      onReset={reset}
    />
  );
}
