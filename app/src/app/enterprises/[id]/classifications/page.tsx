import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import { FormField } from "@/components/form/form-field";

export const metadata: Metadata = {
  title: "Enterprise | Classifications",
};

export default async function EnterpriseClassificationsPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
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

  const primaryActivity = primaryUnit.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const secondaryActivity = primaryUnit.activity?.find(
    (act) => act.type === "secondary"
  )?.activity_category;

  return (
    <DetailsPage
      title="Classifications"
      subtitle="Classifications characteristics such as activity categories, legal form and sector"
    >
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
        {primaryLegalUnit && (
          <>
            <FormField
              label="Legal Form"
              name="legal_form_id"
              value={
                primaryLegalUnit.legal_form
                  ? `${primaryLegalUnit.legal_form.code} ${primaryLegalUnit.legal_form.name}`
                  : null
              }
              response={null}
              readonly
            />
            <FormField
              label="Sector"
              name="sector_id"
              value={
                primaryLegalUnit.sector
                  ? `${primaryLegalUnit.sector.code} ${primaryLegalUnit.sector.name}`
                  : null
              }
              response={null}
              readonly
            />
          </>
        )}
      </form>
    </DetailsPage>
  );
}
