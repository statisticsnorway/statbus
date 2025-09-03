"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function DemographicInfoForm({ id }: { readonly id: string }) {
  const { data, isLoading, error } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const establishment = data?.establishment?.[0];
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
