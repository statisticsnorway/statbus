"use client";
import React, { useActionState, useEffect } from "react";
import { FormField } from "@/components/form/form-field";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { EditableFieldGroup } from "@/components/form/editable-field-group";
import { updateLegalUnit } from "../update-legal-unit-server-actions";
import { useDetailsPageData } from "@/atoms/edits";
import { SelectFormField } from "@/components/form/select-form-field";
import { DEMOGRAPHIC_COLUMNS } from "@/components/form/read-edit-range";
import { codeListOptions } from "@/components/form/code-list-options";

export default function DemographicInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateLegalUnit.bind(null, id, "demographic-info"),
    null
  );
  const { status, unitSizes } = useDetailsPageData();
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
  const unitSizeOptions = codeListOptions(unitSizes, { optional: true, showCode: false });

  return (
    <EditableFieldGroup
      key={legalUnit?.id}
      fieldGroupId="demographic"
      title="Demographic"
      action={formAction}
      response={state}
      metadata={legalUnit}
      editSource={{
        table: "legal_unit",
        match: { id: parseInt(id, 10) },
        column: [...DEMOGRAPHIC_COLUMNS],
      }}
      shownValues={legalUnit ?? undefined}
    >
      {({ isEditing, valueOf }) => (
        <div className="space-y-4">
          <SelectFormField
            label="Status"
            name="status_id"
            value={valueOf("status_id", legalUnit?.status?.id)}
            options={statusOptions}
            readonly={!isEditing}
            placeholder="Select a status"
          />
          <FormField
            label="Birth date"
            name="birth_date"
            value={valueOf("birth_date", legalUnit?.birth_date)}
            response={null}
            readonly={!isEditing}
          />
          <FormField
            label="Death date"
            name="death_date"
            value={valueOf("death_date", legalUnit?.death_date)}
            response={null}
            readonly={!isEditing}
          />
          <SelectFormField
            label="Unit size"
            name="unit_size_id"
            value={valueOf("unit_size_id", legalUnit?.unit_size_id)}
            options={unitSizeOptions}
            readonly={!isEditing}
            placeholder="Select a unit size"
          />
        </div>
      )}
    </EditableFieldGroup>
  );
}
