import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { Metadata } from "next";
import ContactInfoForm from "./contact-info-form";

export const metadata: Metadata = {
  title: "Enterprise | Contact",
};

export default async function EnterpriseContactPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
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