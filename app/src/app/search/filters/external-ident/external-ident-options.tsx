"use client";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback, useMemo } from "react";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { Tables } from "@/lib/database.types";
import { externalIdentDeriveStateUpdateFromValues } from "../url-search-params";

export default function ExternalIdentOptions({ externalIdentType }: {
  readonly externalIdentType: Tables<"external_ident_type_ordered">;
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [externalIdentType.code!]: selected = [] },
    },
  } = useSearchContext();

  const update = useCallback((value: string | null) => {
    modifySearchState(
      externalIdentDeriveStateUpdateFromValues(externalIdentType, value)
    );
  }, [modifySearchState, externalIdentType]);

  const reset = useCallback(() => {
    modifySearchState(
      externalIdentDeriveStateUpdateFromValues(externalIdentType, null)
    );
  }, [modifySearchState, externalIdentType]);

  const selected_value = useMemo(() => 
    selected[0] ? { operator: "eq", operand: selected[0] } : null
  , [selected]);

  return (
    <ConditionalFilter
      className="p-2 h-9"
      title={externalIdentType.name!}
      selected={selected_value}
      onChange={({operand}) => update(operand)}
      onReset={reset}
    />
  );
}
