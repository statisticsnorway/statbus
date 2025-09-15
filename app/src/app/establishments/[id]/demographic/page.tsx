import { Metadata } from "next";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import DemographicInfoForm from "./demographic-info-form";

export const metadata: Metadata = {
  title: "Establishment | Demographic",
};

export default async function EstablishmentDemographicPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Demographic characteristics"
      subtitle="Demographic characteristics such as unit activity start and end dates, current status"
    >
      <DemographicInfoForm id={id} />
    </DetailsPage>
  );
}
