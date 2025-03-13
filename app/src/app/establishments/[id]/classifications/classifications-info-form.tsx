"use client";
import { FormField } from "@/components/form/form-field";

export default function ClassificationsInfoForm({
  establishment,
}: {
  readonly establishment: Establishment;
}) {
  const primaryActivity = establishment.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const secondaryActivity = establishment.activity?.find(
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
    </form>
  );
}
