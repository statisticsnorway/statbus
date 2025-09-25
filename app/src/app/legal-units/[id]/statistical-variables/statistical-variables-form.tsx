"use client";
import { useBaseData } from "@/atoms/base-data";
import { useStatisticalUnitStats } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { Tables } from "@/lib/database.types";
import { useActionState, useEffect, useState } from "react";
import { EditableFieldWithMetadata } from "@/components/form/editable-field-with-metadata";
import { updateStatisticalVariables } from "../update-legal-unit-server-actions";

export default function StatisticalVariablesForm({
  id,
}: {
  readonly id: string;
}) {
  const { statDefinitions } = useBaseData();
  const { data, isLoading, error, revalidate } = useStatisticalUnitStats(
    id,
    "legal_unit"
  );
  const [statsState, statsAction] = useActionState(
    updateStatisticalVariables.bind(null, id, "legal_unit"),
    null
  );
  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);
  useEffect(() => {
    if (statsState?.status === "success") {
      revalidate();
    }
  }, [statsState, revalidate]);
  if (!isClient) {
    return <Loading />;
  }
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  return (
    <div>
      {statDefinitions.map(
        (statDefinition: Tables<"stat_definition_active">) => {
          const value = data?.stats[statDefinition.code!];
          return (
            <EditableFieldWithMetadata
              key={statDefinition.code}
              label={statDefinition.name ?? statDefinition.code!}
              fieldId={`${statDefinition.code}`}
              name="value"
              value={value || ""}
              response={statsState}
              formAction={statsAction}
              statType={statDefinition.type!}
              statDefinitionId={statDefinition.id!}
            />
          );
        }
      )}
    </div>
  );
}
