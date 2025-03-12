import { Metadata } from "next";
import { notFound } from "next/navigation";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import ContactInfoForm from "./contact-info-form";

export const metadata: Metadata = {
  title: "Legal Unit | Contact",
};

export default async function LegalUnitContactPage({
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
      title="Contact Info"
      subtitle="Contact information such as email, phone and postal address"
    >
      <ContactInfoForm legalUnit={legalUnit} id={id} />
    </DetailsPage>
  );
}
