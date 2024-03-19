import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import {
  getEnterpriseById,
  getStatisticalUnitHierarchy,
} from "@/components/statistical-unit-details/requests";
import React from "react";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { FormField } from "@/components/form/form-field";

export default async function EnterpriseDetailsPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { enterprise, error } = await getEnterpriseById(id);
  const { hierarchy, error: hierarchyError } =
    await getStatisticalUnitHierarchy(parseInt(id, 10), "enterprise");

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (hierarchyError) {
    throw new Error(hierarchyError.message, { cause: hierarchyError });
  }

  if (!enterprise || !hierarchy) {
    notFound();
  }

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit.find(
    (lu) => lu.primary_for_enterprise
  );
  if (!primaryLegalUnit) {
    throw new Error("No primary legal unit found");
  }

  return (
    <DetailsPage
      title="General Info"
      subtitle="General information such as name, sector"
    >
      <form className="space-y-8">
        <FormField
          readonly
          label="Name"
          name="name"
          value={primaryLegalUnit.name}
          response={null}
        />

        <FormField
          readonly
          label="Tax Register ID"
          name="tax_ident"
          value={primaryLegalUnit.tax_ident}
          response={null}
        />
      </form>

      <InfoBox>
        <p>
          The information above is derived from the primary legal unit &nbsp;
          <Link
            className="underline"
            href={`/legal-units/${primaryLegalUnit.id}`}
          >
            {primaryLegalUnit.name}
          </Link>
          .
        </p>
        <p>
          If you need to update this information, update the primary legal unit
          or change the primary legal unit altogether.
        </p>
      </InfoBox>
    </DetailsPage>
  );
}
