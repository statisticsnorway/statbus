import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import ClassificationsInfoForm from "./classifications-info-form";

export const metadata: Metadata = {
  title: "Legal Unit | Classifications",
};

export default async function LegalUnitClassificationsPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { unit, error } = await getStatisticalUnitDetails(
    parseInt(id, 10),
    "legal_unit"
  );

  const legalUnit = unit?.legal_unit?.[0];
  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!legalUnit) {
    notFound();
  }

  return (
    <DetailsPage
      title="Classifications"
      subtitle="Classifications such as activity categories, legal form and sector"
    >
      <ClassificationsInfoForm legalUnit={legalUnit} />
    </DetailsPage>
  );
}
