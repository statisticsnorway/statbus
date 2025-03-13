"use client";
import { useBaseData } from "@/app/BaseDataClient";
import { FormField } from "@/components/form/form-field";

export default function StatisticalVariablesForm({
  legalUnitStats,
}: {
  readonly legalUnitStats: StatisticalUnitStats;
}) {
  const { statDefinitions } = useBaseData();

  return (
    <form className="space-y-4">
      {statDefinitions.map((statDefinition) => {
        const value = legalUnitStats.stats?.[statDefinition.code!];
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
