"use client";
import { useBaseData } from "@/atoms/base-data";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
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
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );
  const stats = data?.legal_unit?.[0].stat_for_unit;
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
          const stat = stats?.find(
            (s) => s.stat_definition_id === statDefinition.id
          );
          const value =
            stat?.value_int ?? stat?.value_float ?? stat?.value_string;
          return (
            <EditableFieldWithMetadata
              key={statDefinition.code}
              label={statDefinition.name ?? statDefinition.code!}
              fieldId={statDefinition.code!}
              fieldName={`value_${statDefinition.type}`}
              value={value || ""}
              response={statsState}
              formAction={statsAction}
              hiddenFields={{ stat_definition_id: statDefinition.id! }}
              metadata={stat}
            />
          );
        }
      )}
    </div>
  );
}
