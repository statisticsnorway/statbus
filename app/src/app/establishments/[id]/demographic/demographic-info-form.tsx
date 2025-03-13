"use client";
import { FormField } from "@/components/form/form-field";

export default function DemographicInfoForm({
  establishment,
}: {
  readonly establishment: Establishment;
}) {
  return (
    <form className="space-y-4">
      <FormField
        label="Status"
        name="status"
        value={establishment?.status?.name}
        response={null}
        readonly
      />
      <FormField
        label="Birth date"
        name="birth_date"
        value={establishment?.birth_date}
        response={null}
        readonly
      />
      <FormField
        label="Death date"
        name="death_date"
        value={establishment?.death_date}
        response={null}
        readonly
      />
    </form>
  );
}
