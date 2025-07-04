"use client";
import { useBaseData } from "@/atoms/base-data";
import { FormField } from "@/components/form/form-field";

export default function StatisticalVariablesForm({
  enterpriseStats,
}: {
  readonly enterpriseStats: StatisticalUnitStats;
}) {
  const { statDefinitions } = useBaseData();

  return (
    <form className="space-y-4">
      {statDefinitions.map((statDefinition) => {
        const value =
          enterpriseStats?.stats_summary?.[statDefinition.code]?.sum;
        return (
          <FormField
            key={statDefinition.code}
            label={statDefinition.name ?? statDefinition.code!}
            name={`stats.${statDefinition.code}`}
            value={value}
            response={null}
            readonly
          />
        );
      })}
    </form>
  );
}
