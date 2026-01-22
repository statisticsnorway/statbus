"use client";
import { useSearchFilters } from "@/atoms/search";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useCallback, useMemo } from "react";
import { Tables } from "@/lib/database.types";
import { statisticalVariableParse } from "../url-search-params";
import { ConditionalValue } from "@/app/search/search";

export default function StatisticalVariablesOptions({ statDefinition }:
  {
    readonly statDefinition: Tables<"stat_definition_ordered">;
  }) {
  const { filters, updateFilters } = useSearchFilters();
  const currentFilterString = filters[statDefinition.code!] as string | null;

  const parsedValue = useMemo(() =>
    statisticalVariableParse(currentFilterString) // Parse the string value from filters
    , [currentFilterString]);

  const update = useCallback(async (value: ConditionalValue | null) => {
    const newFilters = { ...filters };
    if (value) {
      // Convert ConditionalValue to string format
      if ('conditions' in value) {
        // Multiple conditions: "op:val,op:val"
        const conditionsStr = value.conditions
          .map(c => `${c.operator}:${c.operand}`)
          .join(',');
        newFilters[statDefinition.code!] = conditionsStr;
      } else {
        // Single condition: "op:val"
        newFilters[statDefinition.code!] = `${value.operator}:${value.operand}`;
      }
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
