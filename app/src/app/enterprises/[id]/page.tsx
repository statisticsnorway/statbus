import {notFound} from "next/navigation";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getEnterpriseById} from "@/app/_requests/enterprise-requests";

export default async function EnterpriseDetailsPage({params: {id}}: { readonly params: { id: string } }) {
  const {enterprise, error} = await getEnterpriseById(id);
  const name = `Enterprise ${enterprise?.id}`;

  if (error) {
    throw error
  }

  if (!enterprise) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, sector">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show general information for {name}
      </p>
    </DetailsPage>
  )
}
