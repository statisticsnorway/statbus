import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEnterpriseById} from "@/app/enterprises/[id]/enterprise-requests";

export default async function EnterpriseInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEnterpriseById(id);
  const name = `Enterprise ${unit?.id}`;

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Data Dump" subtitle={`This section shows the raw data we have on ${name}`}>
      <DataDump data={unit}/>
    </DetailsPage>
  )
}

