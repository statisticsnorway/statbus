"use client";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function DemographicInfoForm({ id }: { readonly id: string }) {
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

  return (
    <form className="space-y-4">
      <FormField
        label="Status"
        name="status"
        value={primaryUnit?.status?.name}
        response={null}
        readonly
      />
      <FormField
        label="Birth date"
        name="birth_date"
        value={primaryUnit?.birth_date}
        response={null}
        readonly
      />
      <FormField
        label="Death date"
        name="death_date"
        value={primaryUnit?.death_date}
        response={null}
        readonly
      />
    </form>
  );
}
