"use client";
import { useSearchContext } from "@/app/search/use-search-context";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useCallback, useEffect } from "react";

export default function StatisticalVariablesOptions({
  label,
  code,
  selected: initialSelected,
}: {
  readonly label: string;
  readonly code: string;
  readonly selected?: { operator?: string; value: string | null };
}) {
  const {
    modifySearchState,
    searchState: {
      values: { [code]: selected = [] },
    },
  } = useSearchContext();

  useEffect(() => {
    if (initialSelected) {
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: code,
          api_param_name: `stats_summary->${code}->sum`,
          api_param_value: `${initialSelected.operator}.${initialSelected.value}`,
          app_param_values: [
            `${initialSelected.operator}.${initialSelected.value}`,
          ],
        },
      });
    }
  }, [modifySearchState, code, initialSelected]);

  const update = useCallback(
    ({ operator, value }: { operator: string; value: string }) => {
      modifySearchState({
        type: "set_query",
        payload: {
          app_param_name: code,
          api_param_name: `stats_summary->${code}->sum`,
          api_param_value: operator && value ? `${operator}.${value}` : null,
          app_param_values: operator && value ? [`${operator}.${value}`] : [],
        },
      });
    },
    [modifySearchState, code]
  );

  const reset = useCallback(() => {
    modifySearchState({
      type: "set_query",
      payload: {
        app_param_name: code,
        api_param_name: `stats_summary->${code}->sum`,
        api_param_value: null,
        app_param_values: [],
      },
    });
  }, [modifySearchState, code]);

  const [operator, value] = selected[0]?.split(".") ?? [];

  return (
    <ConditionalFilter
      className="p-2 h-9"
      title={label}
      selected={operator && value ? { value, operator } : undefined}
      onChange={update}
      onReset={reset}
    />
  );
}
