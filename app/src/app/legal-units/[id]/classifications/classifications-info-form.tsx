"use client";
import { FormField } from "@/components/form/form-field";

export default function ClassificationsInfoForm({
  legalUnit,
}: {
  readonly legalUnit: LegalUnit;
}) {
  const primaryActivity = legalUnit.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const secondaryActivity = legalUnit.activity?.find(
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
          legalUnit.legal_form
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
          legalUnit.sector
            ? `${legalUnit.sector.code} ${legalUnit.sector.name}`
            : null
        }
        response={null}
        readonly
      />
    </form>
  );
}
