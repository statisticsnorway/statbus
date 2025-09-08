"use client";
import StatisticalVariablesOptions from "@/app/search/filters/statistical-variables/statistical-variables-options";
import { FilterWrapper } from "../../components/filter-wrapper";
import { statDefinitionsAtom } from "@/atoms/base-data";
import { useAtomValue } from "jotai";

export default function StatisticalVariablesFilter() {
  const statDefinitions = useAtomValue(statDefinitionsAtom);

  return (
    <>
      {statDefinitions?.map((statDefinition) => (
        <FilterWrapper 
          key={"stat_var"+statDefinition.code!}
          columnCode="statistic"
          statCode={statDefinition.code}
        >
          <StatisticalVariablesOptions
            statDefinition={statDefinition}
          />
        </FilterWrapper>
      )) ?? []}
    </>
  );
}

