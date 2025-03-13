import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import GeneralInfoForm from "./general-info/general-info-form";

export const metadata: Metadata = {
  title: "Establishment | General Info",
};

export default async function EstablishmentGeneralInfoPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { unit, error } = await getStatisticalUnitDetails(
    parseInt(id),
    "establishment"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  const establishment = unit?.establishment?.[0];

  if (!establishment) {
    notFound();
  }

  return (
    <DetailsPage
      title="Identification"
      subtitle="Identification information such as name, id(s) and physical address"
    >
      <GeneralInfoForm establishment={establishment} />
    </DetailsPage>
  );
}
