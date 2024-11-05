"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchContext } from "@/app/search/use-search-context";
import { useCallback } from "react";
import { DATA_SOURCE, dataSourceDeriveStateUpdateFromValues } from "@/app/search/filters/url-search-params";
import { SearchFilterOption } from "../../search";
import { Tables } from "@/lib/database.types";


export default function DataSourceOptions({
  options,
  dataSources,
}: {
  readonly options: SearchFilterOption[];
  readonly dataSources: Tables<"data_source_used">[];
}) {
  const {
    modifySearchState,
    searchState: {
      appSearchParams: { [DATA_SOURCE]: selected = [] },
    },
  } = useSearchContext();

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const values = selected.includes(value)
        ? selected.filter((v) => v !== value)
        : [...selected, value];

      modifySearchState(dataSourceDeriveStateUpdateFromValues(values, dataSources));
    },
    [selected, modifySearchState, dataSources]
  );

  const reset = useCallback(() => {
    modifySearchState(dataSourceDeriveStateUpdateFromValues([], []));
  }, [modifySearchState]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Data Source"
      options={options}
      selectedValues={selected}
      onToggle={toggle}
      onReset={reset}
    />
  );
}
