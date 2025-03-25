import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import { FormField } from "@/components/form/form-field";

export const metadata: Metadata = {
  title: "Enterprise | Demographic",
};

export default async function EnterpriseDemographicPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "enterprise"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!hierarchy) {
    notFound();
  }

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  if (!primaryUnit) {
    notFound();
  }
  return (
    <DetailsPage
      title="Demographic characteristics"
      subtitle="Demographic characteristics such as unit activity start and end dates, current status"
    >
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
    </DetailsPage>
  );
}
