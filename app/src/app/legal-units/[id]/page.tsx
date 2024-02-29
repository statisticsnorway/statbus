import {Metadata} from "next";
import {notFound} from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getLegalUnitById} from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | General Info"
}

export default async function LegalUnitGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const {legalUnit, error} = await getLegalUnitById(id)

  if (error) {
    throw new Error(error.message, { cause: error})
  }

  if (!legalUnit) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, id, sector and primary activity">
      <GeneralInfoForm values={legalUnit} id={id}/>
    </DetailsPage>
  )
}
