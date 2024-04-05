"use client";
import { useSearchContext } from "@/app/search/use-search-context";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useEffect, useState } from "react";

export default function StatisticalVariablesOptions({
  label,
  code,
  selected: initialSelected,
}: {
  readonly label: string;
  readonly code: string;
  readonly selected?: { operator?: PostgrestOperator; value: string | null };
}) {
  const context = useSearchContext();
  const [selected, setSelected] = useState(initialSelected);

  useEffect(() => {
    context.dispatch({
      type: "set_query",
      payload: {
        name: code,
        query: selected ? `${selected.operator}.${selected.value}` : null,
      },
    });
  }, [selected]);

  return (
    <ConditionalFilter
      className="p-2 h-9"
      title={label}
      selected={selected}
      onChange={({ operator, value }) => {
        setSelected({ operator, value });
      }}
      onReset={() => {
        setSelected(undefined);
      }}
    />
  );
}
