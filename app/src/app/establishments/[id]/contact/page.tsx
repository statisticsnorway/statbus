import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getStatisticalUnitDetails } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import ContactInfoForm from "./contact-info-form";

export const metadata: Metadata = {
  title: "Establishment | Contact",
};

export default async function EstablishmentContactPage(
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
      title="Contact Info"
      subtitle="Contact information such as email, phone and postal address"
    >
      <ContactInfoForm establishment={establishment} />
    </DetailsPage>
  );
}
