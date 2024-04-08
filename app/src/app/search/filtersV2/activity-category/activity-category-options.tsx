"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";

export default function ActivityCategoryOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const { dispatch } = useSearchContext();
  const [selected, setSelected] = useState(initialSelected);

  useEffect(() => {
    const value = selected[0];
    dispatch({
      type: "set_query",
      payload: {
        name: "primary_activity_category_path",
        query: value ? `cd.${value}` : value === null ? "is.null" : null,
        urlValue: value,
      },
    });
  }, [dispatch, selected]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Activity Category"
      options={options}
      selectedValues={selected}
      onToggle={({ value }) => {
        setSelected((prev) => (prev.includes(value) ? [] : [value]));
      }}
      onReset={() => {
        setSelected([]);
      }}
    />
  );
}
