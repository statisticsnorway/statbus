"use client";
import { useSearchFilters } from "@/atoms/search";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useCallback, useMemo } from "react";
import { Tables } from "@/lib/database.types";
import { statisticalVariableParse } from "../url-search-params";

export default function StatisticalVariablesOptions({ statDefinition }:
  {
    readonly statDefinition: Tables<"stat_definition_ordered">;
  }) {
  const { filters, updateFilters } = useSearchFilters();
  const currentFilterString = filters[statDefinition.code!] as string | null;

  const parsedValue = useMemo(() =>
    statisticalVariableParse(currentFilterString) // Parse the string value from filters
    , [currentFilterString]);

  const update = useCallback(async (value : {operator: string, operand: string} | null) => {
    const newFilters = { ...filters };
    if (value && value.operand !== undefined && value.operand !== null && String(value.operand).trim() !== '') {
      // Format the value as a string, e.g., "operator:operand"
      newFilters[statDefinition.code!] = `${value.operator}:${value.operand}`;
    } else {
      delete newFilters[statDefinition.code!];
    }
    updateFilters(newFilters);
  }, [filters, updateFilters, statDefinition.code]);

  const reset = useCallback(async () => {
    const newFilters = { ...filters };
    delete newFilters[statDefinition.code!];
    updateFilters(newFilters);
  }, [filters, updateFilters, statDefinition.code]);

  return (
    <ConditionalFilter
      className="p-2 h-9"
      title={statDefinition.name!}
      selected={parsedValue}
      onChange={update} // Pass `update` which receives the new filter value
      onReset={reset}
    />
  );
}
