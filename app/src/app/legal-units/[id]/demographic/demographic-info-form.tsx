"use client";
import React, { useActionState, useEffect } from "react";
import { FormField } from "@/components/form/form-field";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { EditableFieldGroup } from "@/components/form/editable-field-group";
import { updateLegalUnit } from "../update-legal-unit-server-actions";
import { useDetailsPageData } from "@/atoms/edits";
import { SelectFormField } from "@/components/form/select-form-field";

export default function DemographicInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateLegalUnit.bind(null, id),
    null
  );
  const { status } = useDetailsPageData();
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );
  useEffect(() => {
    if (state?.status === "success") {
      revalidate();
    }
  }, [state, revalidate]);
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const legalUnit = data?.legal_unit?.[0];
  const statusOptions = status.map((s) => ({
    value: s.id,
    label: `${s.name}`,
  }));
  return (
    <EditableFieldGroup
      key={legalUnit?.id}
      fieldGroupId="demographic"
      title="Demographic"
      action={formAction}
      response={state}
      metadata={legalUnit}
    >
      {({ isEditing }) => (
        <div className="space-y-4">
          <SelectFormField
            label="Status"
            name="status_id"
            value={legalUnit?.status?.id}
            options={statusOptions}
            readonly={!isEditing}
            placeholder="Select a status"
          />
          <FormField
            label="Birth date"
            name="birth_date"
            value={legalUnit?.birth_date}
            response={null}
            readonly={!isEditing}
          />
          <FormField
            label="Death date"
            name="death_date"
            value={legalUnit?.death_date}
            response={null}
            readonly={!isEditing}
          />
        </div>
      )}
    </EditableFieldGroup>
  );
}
