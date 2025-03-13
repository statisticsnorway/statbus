import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import ClassificationsInfoForm from "./classifications-info-form";

export const metadata: Metadata = {
  title: "Establishment | Classifications",
};

export default async function EstablishmentClassificationsPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { unit, error } = await getStatisticalUnitDetails(
    parseInt(id, 10),
    "establishment"
  );

  const establishment = unit?.establishment?.[0];
  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!establishment) {
    notFound();
  }

  return (
    <DetailsPage
      title="Classifications"
      subtitle="Classifications characteristics such as activity categories, legal form and sector"
    >
      <ClassificationsInfoForm establishment={establishment} />
    </DetailsPage>
  );
}
