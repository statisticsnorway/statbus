import {Metadata} from "next";
import {notFound} from "next/navigation";
import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getLegalUnitById} from "@/components/statistical-unit-details/requests";

export const metadata: Metadata = {
  title: "Legal Unit | Inspect"
}

export default async function LegalUnitInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const {legalUnit, error} = await getLegalUnitById(id)

  if (error) {
    throw error
  }

  if (!legalUnit) {
    notFound()
  }

  return (
    <DetailsPage title="Data Dump" subtitle={`This section shows the raw data we have on ${legalUnit.name}`}>
      <DataDump data={legalUnit}/>
    </DetailsPage>
  )
}
