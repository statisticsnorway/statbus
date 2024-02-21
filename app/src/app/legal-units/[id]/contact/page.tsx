import {Metadata} from "next";
import {notFound} from "next/navigation";
import ContactInfoForm from "@/app/legal-units/[id]/contact/contact-info-form";
import {getLegalUnitById} from "@/app/legal-units/[id]/legal-unit-requests";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export const metadata: Metadata = {
  title: "Legal Unit | Contact"
}

export default async function LegalUnitContactPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id);

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <ContactInfoForm values={unit} id={id}/>
    </DetailsPage>
  )
}
