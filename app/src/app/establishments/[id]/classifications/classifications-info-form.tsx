"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { updateActivity } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useActionState, useEffect } from "react";
import { useDetailsPageData } from "@/atoms/edits";
import { EditableSelectWithMetadata } from "@/components/form/editable-field-with-select";

export default function ClassificationsInfoForm({
  id,
}: {
  readonly id: string;
}) {
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  const { activityCategories } = useDetailsPageData();
  const [primaryActivityState, primaryActivityAction] = useActionState(
    updateActivity.bind(null, id, "establishment"),
    null
  );

  const [secondaryActivityState, secondaryActivityAction] = useActionState(
    updateActivity.bind(null, id, "establishment"),
    null
  );

  useEffect(() => {
    if (
      primaryActivityState?.status === "success" ||
      secondaryActivityState?.status === "success"
    ) {
      revalidate();
    }
  }, [primaryActivityState, secondaryActivityState, revalidate]);
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const establishment = data?.establishment?.[0];
  const primaryActivity = establishment?.activity?.find(
    (act) => act.type === "primary"
  );
  const secondaryActivity = establishment?.activity?.find(
    (act) => act.type === "secondary"
  );
  const activityCategoryOptions = activityCategories.map(
    (activityCategory) => ({
      value: activityCategory.id!,
      label: `${activityCategory.code} ${activityCategory.name}`,
    })
  );
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
        hiddenFields={{ type: "primary" }}
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
        hiddenFields={{ type: "secondary" }}
      />
    </div>
  );
}
