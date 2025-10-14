"use client";
import { useBaseData } from "@/atoms/base-data";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { useActionState, useEffect, useState } from "react";
import { updateStatisticalVariables } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { EditableFieldWithMetadata } from "@/components/form/editable-field-with-metadata";
import { InfoBox } from "@/components/info-box";

export default function StatisticalVariablesForm({
  id,
}: {
  readonly id: string;
}) {
  const [statsState, statsAction] = useActionState(
    updateStatisticalVariables.bind(null, id, "establishment"),
    null
  );
  const { statDefinitions } = useBaseData();
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  const stats = data?.establishment?.[0].stat_for_unit;
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
      {data?.establishment?.[0].status?.used_for_counting === false && (
        <InfoBox>
          <p className="text-sm">
            This unit has status{" "}
            <strong>{data?.establishment?.[0].status?.name}</strong>, therefore
            the statistical variables are not included in aggregates.
          </p>
        </InfoBox>
      )}
      {statDefinitions.map((statDefinition) => {
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
      })}
    </div>
  );
}
