"use client";
import { useSearchContext } from "@/app/search/use-search-context";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useCallback, useMemo } from "react";
import { Tables } from "@/lib/database.types";
import { statisticalVariableParse, statisticalVariableDeriveStateUpdateFromValue } from "../url-search-params";

export default function StatisticalVariablesOptions({ statDefinition }:
  {
    readonly statDefinition: Tables<"stat_definition_ordered">;
  }) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [statDefinition.code!]: selected = [] },
    },
  } = useSearchContext();

  const parsedValue = useMemo(() =>
    statisticalVariableParse(selected?.[0])
    , [selected]);

  const update = useCallback((value : {operator: string, operand: string} | null) => {
    modifySearchState(
      statisticalVariableDeriveStateUpdateFromValue(
        statDefinition,
        value,
      )
    );
  }, [modifySearchState, statDefinition]);

  const reset = useCallback(() => {
    modifySearchState(
      statisticalVariableDeriveStateUpdateFromValue(statDefinition, null)
    );
  }, [modifySearchState, statDefinition]);

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
