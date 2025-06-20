import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import GeneralInfoForm from "./general-info/general-info-form";

export const metadata: Metadata = {
  title: "Establishment | General Info",
};

export default async function EstablishmentGeneralInfoPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

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
      <GeneralInfoForm id={id} establishment={establishment} />
    </DetailsPage>
  );
}
