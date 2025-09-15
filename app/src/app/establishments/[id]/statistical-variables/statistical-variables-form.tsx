"use client";
import { useBaseData } from "@/atoms/base-data";
import { useStatisticalUnitStats } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { useEffect, useState } from "react";

export default function StatisticalVariablesForm({
  id,
}: {
  readonly id: string;
}) {
  const { statDefinitions } = useBaseData();
  const { data, isLoading, error } = useStatisticalUnitStats(
    id,
    "establishment"
  );
  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);

  if (!isClient) {
    return <Loading />;
  }
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }

  return (
    <form className="space-y-4">
      {statDefinitions.map((statDefinition) => {
        const value = data?.stats?.[statDefinition.code!];
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
