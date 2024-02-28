import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEnterpriseById} from "@/components/statistical-unit-details/requests";

export default async function EnterpriseInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getEnterpriseById(id)

  if (error) {
    throw error
  }

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Data Dump" subtitle={`This section shows the raw data we have on ${unit.id}`}>
      <DataDump data={unit}/>
    </DetailsPage>
  )
}

