"use client";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { DisplayFormField } from "@/components/form/display-field";

export default function ClassificationsInfoForm({
  id,
}: {
  readonly id: string;
}) {
  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "enterprise"
  );
  if (error || (!isLoading && !hierarchy)) {
    return <UnitNotFound />;
  }
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  const primaryActivity = primaryUnit?.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const secondaryActivity = primaryUnit?.activity?.find(
    (act) => act.type === "secondary"
  )?.activity_category;

  return (
    <form className="space-y-4">
      <DisplayFormField
        label="Primary Activity category"
        name="primary_activity_category_id"
        value={
          primaryActivity
            ? `${primaryActivity.code} ${primaryActivity.name}`
            : null
        }
      />
      <DisplayFormField
        label="Secondary Activity category"
        name="secondary_activity_category_id"
        value={
          secondaryActivity
            ? `${secondaryActivity.code} ${secondaryActivity.name}`
            : null
        }
      />
      {primaryLegalUnit && (
        <>
          <DisplayFormField
            label="Legal Form"
            name="legal_form_id"
            value={
              primaryLegalUnit.legal_form
                ? `${primaryLegalUnit.legal_form.code} ${primaryLegalUnit.legal_form.name}`
                : null
            }
          />
          <DisplayFormField
            label="Sector"
            name="sector_id"
            value={
              primaryLegalUnit.sector
                ? `${primaryLegalUnit.sector.code} ${primaryLegalUnit.sector.name}`
                : null
            }
          />
        </>
      )}
    </form>
  );
}
