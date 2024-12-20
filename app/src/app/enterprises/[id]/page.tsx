import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import {
  getEnterpriseById,
  getStatisticalUnitHierarchy,
} from "@/components/statistical-unit-details/requests";
import React from "react";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { Metadata } from "next";
import GeneralInfoForm from "./general-info/general-info-form";

export const metadata: Metadata = {
  title: "Enterprise | General Info",
};

export default async function EnterpriseDetailsPage({
  params: { id }
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

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  if (!primaryUnit) {
    throw new Error("No primary legal unit or establishment found");
  }

  return (
    <DetailsPage
      title="General Info"
      subtitle="General information such as name, sector"
    >
      <GeneralInfoForm values={primaryUnit} />
      <InfoBox>
        <p>
          The information above is derived from the primary
          {primaryLegalUnit ? " legal unit" : " establishment"} &nbsp;
          <Link
            className="underline"
            href={`/${primaryLegalUnit ? "legal-units" : "establishments"}/${primaryUnit.id}`}
          >
            {primaryUnit.name}
          </Link>
          .
        </p>
        <p>
          If you need to update this information, update the primary
          {primaryLegalUnit
            ? " legal unit or change the primary legal unit altogether"
            : " establishment"}
          .
        </p>
      </InfoBox>
    </DetailsPage>
  );
}
