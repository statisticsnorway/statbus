"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useEffect, useState } from "react";
import { UNIT_TYPE } from "@/app/search/filtersV2/url-search-params";

interface IProps {
  value: string | null;
}

export default function UnitTypeFilter({ value }: IProps) {
  const context = useSearchContext();
  const initialValue = value?.split(",") ?? ["enterprise"];
  const [selected, setSelected] = useState<(string | null)[]>(initialValue);

  useEffect(() => {
    context.dispatch({
      type: "set_query",
      payload: {
        name: UNIT_TYPE,
        query: selected.length > 0 ? `in.(${selected.join(",")})` : null,
      },
    });
  }, [selected]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Unit Type"
      options={[
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100",
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100",
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100",
        },
      ]}
      selectedValues={selected}
      onReset={() => setSelected([])}
      onToggle={({ value }) => {
        setSelected((prev) =>
          prev.includes(value)
            ? prev.filter((v) => v !== value)
            : [...prev, value]
        );
      }}
    />
  );
}
