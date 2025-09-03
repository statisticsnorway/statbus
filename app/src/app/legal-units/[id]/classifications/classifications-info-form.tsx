"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function ClassificationsInfoForm({
  id,
}: {
  readonly id: string;
}) {
  const { data, isLoading, error } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }

  const legalUnit = data?.legal_unit?.[0];
  const primaryActivity = legalUnit?.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const secondaryActivity = legalUnit?.activity?.find(
    (act) => act.type === "secondary"
  )?.activity_category;

  return (
    <form className="space-y-4">
      <FormField
        label="Primary Activity category"
        name="primary_activity_category_id"
        value={
          primaryActivity
            ? `${primaryActivity.code} ${primaryActivity.name}`
            : null
        }
        response={null}
        readonly
      />
      <FormField
        label="Secondary Activity category"
        name="secondary_activity_category_id"
        value={
          secondaryActivity
            ? `${secondaryActivity.code} ${secondaryActivity.name}`
            : null
        }
        response={null}
        readonly
      />
      <FormField
        label="Legal Form"
        name="legal_form_id"
        value={
          legalUnit?.legal_form
            ? `${legalUnit.legal_form.code} ${legalUnit.legal_form.name}`
            : null
        }
        response={null}
        readonly
      />
      <FormField
        label="Sector"
        name="sector_id"
        value={
          legalUnit?.sector
            ? `${legalUnit.sector.code} ${legalUnit.sector.name}`
            : null
        }
        response={null}
        readonly
      />
    </form>
  );
}
