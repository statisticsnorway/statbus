import { Metadata } from "next";
import { notFound } from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | General Info",
};

export default async function LegalUnitGeneralInfoPage(
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
      title="Identification"
      subtitle="Identification information such as name, id(s) and physical address"
    >
      <GeneralInfoForm legalUnit={legalUnit} id={id} />
    </DetailsPage>
  );
}
