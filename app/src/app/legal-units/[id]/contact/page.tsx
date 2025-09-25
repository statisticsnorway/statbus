import { Metadata } from "next";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import ContactInfoForm from "./contact-info-form";

export const metadata: Metadata = {
  title: "Legal Unit | Contact",
};

export default async function LegalUnitContactPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Contact Info"
      subtitle="Contact information such as email, phone and postal address"
    >
      <ContactInfoForm id={id} />
    </DetailsPage>
  );
}
