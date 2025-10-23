"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { useActionState, useEffect } from "react";
import { updateEstablishment } from "../update-establishment-server-actions";
import { useDetailsPageData } from "@/atoms/edits";
import { EditableFieldGroup } from "@/components/form/editable-field-group";
import { SelectFormField } from "@/components/form/select-form-field";

export default function DemographicInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateEstablishment.bind(null, id, "demographic-info"),
    null
  );
  const { status, unitSizes } = useDetailsPageData();
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  useEffect(() => {
    if (state?.status === "success") {
      revalidate();
    }
  }, [state, revalidate]);
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const establishment = data?.establishment?.[0];
  const statusOptions = status.map((s) => ({
    value: s.id,
    label: `${s.name}`,
  }));
  const unitSizeOptions = unitSizes.map((unitSize) => ({
    value: unitSize.id!,
    label: `${unitSize.name}`,
  }));
  return (
    <EditableFieldGroup
      key={establishment?.id}
      fieldGroupId="demographic"
      title="Demographic"
      action={formAction}
      response={state}
      metadata={establishment}
    >
      {({ isEditing }) => (
        <div className="space-y-4">
          <SelectFormField
            label="Status"
            name="status_id"
            value={establishment?.status?.id}
            options={statusOptions}
            readonly={!isEditing}
            placeholder="Select a status"
          />
          <FormField
            label="Birth date"
            name="birth_date"
            value={establishment?.birth_date}
            response={null}
            readonly={!isEditing}
          />
          <FormField
            label="Death date"
            name="death_date"
            value={establishment?.death_date}
            response={null}
            readonly={!isEditing}
          />
          <SelectFormField
            label="Unit size"
            name="unit_size_id"
            value={establishment?.unit_size_id}
            options={unitSizeOptions}
            readonly={!isEditing}
            placeholder="Select a unit size"
          />
        </div>
      )}
    </EditableFieldGroup>
  );
}
