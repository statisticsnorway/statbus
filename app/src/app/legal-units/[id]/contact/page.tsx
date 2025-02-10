import { Metadata } from "next";
import { notFound } from "next/navigation";
import ContactInfoForm from "@/app/legal-units/[id]/contact/contact-info-form";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | Contact",
};

export default async function LegalUnitContactPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "legal_unit"
  );

  const legalUnit = hierarchy?.enterprise?.legal_unit.find(
    (lu) => lu.id === parseInt(id, 10)
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!legalUnit) {
    notFound();
  }

  return (
    <DetailsPage
      title="Contact Info"
      subtitle="Contact information such as email, phone, and addresses"
    >
      <ContactInfoForm values={legalUnit.contact} id={id} />
    </DetailsPage>
  );
}
