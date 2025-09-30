"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { useActionState, useEffect } from "react";
import {
  updateActivity,
  updateLegalUnit,
} from "../update-legal-unit-server-actions";
import { useDetailsPageData } from "@/atoms/edits";
import { EditableSelectWithMetadata } from "@/components/form/editable-field-with-select";

export default function ClassificationsInfoForm({
  id,
}: {
  readonly id: string;
}) {
  const { data, isLoading, revalidate, error } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );
  const { activityCategories, legalForms, sectors } = useDetailsPageData();
  const [primaryActivityState, primaryActivityAction] = useActionState(
    updateActivity.bind(null, id, "primary", "legal_unit"),
    null
  );

  const [secondaryActivityState, secondaryActivityAction] = useActionState(
    updateActivity.bind(null, id, "secondary", "legal_unit"),
    null
  );

  const [sectorState, sectorAction] = useActionState(
    updateLegalUnit.bind(null, id),
    null
  );
  const [legalFormState, legalFormAction] = useActionState(
    updateLegalUnit.bind(null, id),
    null
  );

  useEffect(() => {
    if (
      primaryActivityState?.status === "success" ||
      secondaryActivityState?.status === "success" ||
      legalFormState?.status === "success" ||
      sectorState?.status === "success"
    ) {
      revalidate();
    }
  }, [
    primaryActivityState,
    secondaryActivityState,
    legalFormState,
    sectorState,
    revalidate,
  ]);
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const legalUnit = data?.legal_unit?.[0];
  const primaryActivity = legalUnit?.activity?.find(
    (act) => act.type === "primary"
  );
  const secondaryActivity = legalUnit?.activity?.find(
    (act) => act.type === "secondary"
  );

  const activityCategoryOptions = activityCategories.map(
    (activityCategory) => ({
      value: activityCategory.id!,
      label: `${activityCategory.code} ${activityCategory.name}`,
    })
  );
  const legalFormOptions = legalForms.map((legalForm) => ({
    value: legalForm.id!,
    label: `${legalForm.code} ${legalForm.name}`,
  }));
  const sectorOptions = sectors.map((sector) => ({
    value: sector.id!,
    label: `${sector.code} ${sector.name}`,
  }));

  return (
    <div>
      <EditableSelectWithMetadata
        label="Primary Activity category"
        fieldId={`primary_category_id`}
        name="category_id"
        value={
          primaryActivity ? `${primaryActivity?.activity_category.id}` : null
        }
        formAction={primaryActivityAction}
        response={primaryActivityState}
        options={activityCategoryOptions}
        metadata={primaryActivity}
        placeholder="Select an activity category"
      />
      <EditableSelectWithMetadata
        label="Secondary Activity category"
        fieldId="secondary_category_id"
        name="category_id"
        value={
          secondaryActivity
            ? `${secondaryActivity?.activity_category.id}`
            : null
        }
        formAction={secondaryActivityAction}
        response={secondaryActivityState}
        options={activityCategoryOptions}
        metadata={secondaryActivity}
        placeholder="Select an activity category"
      />
      <EditableSelectWithMetadata
        label="Legal Form"
        fieldId="legal_form_id"
        name="legal_form_id"
        value={legalUnit?.legal_form ? `${legalUnit.legal_form.id}` : null}
        formAction={legalFormAction}
        response={legalFormState}
        options={legalFormOptions}
        metadata={legalUnit}
        placeholder="Select a legal form"
      />
      <EditableSelectWithMetadata
        label="Sector"
        fieldId="sector_id"
        name="sector_id"
        value={legalUnit?.sector ? `${legalUnit.sector.id}` : null}
        formAction={sectorAction}
        response={sectorState}
        options={sectorOptions}
        metadata={legalUnit}
        placeholder="Select a sector"
      />
    </div>
  );
}
