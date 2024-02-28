import DataDump from "@/components/data-dump";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEnterpriseById} from "@/app/_requests/enterprise-requests";

export default async function EnterpriseInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const {enterprise, error} = await getEnterpriseById(id);
  const name = `Enterprise ${enterprise?.id}`;

  if (error){
    throw error
  }

  if (!enterprise) {
    notFound()
  }

  return (
    <DetailsPage title="Data Dump" subtitle={`This section shows the raw data we have on ${name}`}>
      <DataDump data={enterprise}/>
    </DetailsPage>
  )
}

