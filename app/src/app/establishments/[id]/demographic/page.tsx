import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import DemographicInfoForm from "./demographic-info-form";

export const metadata: Metadata = {
  title: "Establishment | Demographic",
};

export default async function EstablishmentDemographicPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { unit, error } = await getStatisticalUnitDetails(
    parseInt(id),
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
      title="Demographic characteristics"
      subtitle="Demographic characteristics such as unit activity start and end dates, current status"
    >
      <DemographicInfoForm establishment={establishment} />
    </DetailsPage>
  );
}
