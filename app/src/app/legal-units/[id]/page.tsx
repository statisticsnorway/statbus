import {Metadata} from "next";
import {notFound} from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import {getLegalUnitById} from "@/app/legal-units/[id]/legal-unit-requests";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export const metadata: Metadata = {
  title: "Legal Unit | General Info"
}

export default async function LegalUnitGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id)

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, id, sector and primary activity">
      <GeneralInfoForm values={unit} id={id}/>
    </DetailsPage>
  )
}
