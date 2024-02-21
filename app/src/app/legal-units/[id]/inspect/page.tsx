import {Metadata} from "next";
import {notFound} from "next/navigation";
import {getLegalUnitById} from "@/app/legal-units/[id]/legal-unit-requests";
import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export const metadata: Metadata = {
  title: "Legal Unit | Inspect"
}

export default async function LegalUnitInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id)

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Data Dump" subtitle={`This section shows the raw data we have on ${unit?.name}`}>
      <DataDump data={unit}/>
    </DetailsPage>
  )
}
