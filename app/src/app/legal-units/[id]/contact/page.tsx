import {Metadata} from "next";
import {notFound} from "next/navigation";
import ContactInfoForm from "@/app/legal-units/[id]/contact/contact-info-form";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getLegalUnitById} from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | Contact"
}

export default async function LegalUnitContactPage({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getLegalUnitById(id);

  if (error) {
    throw error
  }

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <ContactInfoForm values={unit} id={id}/>
    </DetailsPage>
  )
}
