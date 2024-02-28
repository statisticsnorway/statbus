import {Metadata} from "next";
import {notFound} from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getLegalUnitById} from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | General Info"
}

export default async function LegalUnitGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getLegalUnitById(id)

  if (error) {
    throw error
  }

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, id, sector and primary activity">
      <GeneralInfoForm values={unit} id={id}/>
    </DetailsPage>
  )
}
