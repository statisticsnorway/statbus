"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";

export default function LegalFormOptions({
  selected: initialSelected,
  options,
}: {
  readonly options: SearchFilterOption[];
  readonly selected: (string | null)[];
}) {
  const context = useSearchContext();
  const [selected, setSelected] = useState(initialSelected);

  useEffect(() => {
    context.dispatch({
      type: "set_query",
      payload: {
        name: "legal_form_code",
        query: selected.length > 0 ? `in.(${selected.join(",")})` : null,
      },
    });
  }, [selected]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Legal Form"
      options={options}
      selectedValues={selected}
      onToggle={({ value }) => {
        setSelected((prev) =>
          prev.includes(value)
            ? prev.filter((v) => v !== value)
            : [...prev, value]
        );
      }}
      onReset={() => {
        setSelected([]);
      }}
    />
  );
}
