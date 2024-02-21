import {getEstablishmentById} from "@/app/establishments/[id]/establishment-requests";
import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";

export default async function EstablishmentDetailsPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEstablishmentById(id);

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Data dump" subtitle={`This section shows the raw data we have on ${unit?.name}`}>
      <DataDump data={unit}/>
    </DetailsPage>
  )
}

