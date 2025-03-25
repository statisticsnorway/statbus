import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import DemographicInfoForm from "./demographic-info-form";

export const metadata: Metadata = {
  title: "Legal Unit | Demographic",
};

export default async function LegalUnitDemographicPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

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
      title="Demographic characteristics"
      subtitle="Demographic characteristics such as unit activity start and end dates, current status"
    >
      <DemographicInfoForm legalUnit={legalUnit} />
    </DetailsPage>
  );
}
