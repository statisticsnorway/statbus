import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";
import {getEnterpriseById} from "@/app/enterprises/[id]/enterprise-requests";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const {enterprise, error} = await getEnterpriseById(id);

  if (error) {
    return  <DetailsPageHeader title="Something went wrong" subtitle={`Could not find an enterprise with ID ${id}`} className="bg-enterprise-50 border-indigo-100"/>
  }

  if (!enterprise) {
    return  <DetailsPageHeader title="Enterprise Not Found" subtitle={`Could not find an enterprise with ID ${id}`} className="bg-enterprise-50 border-indigo-100"/>
  }

  return (
    <DetailsPageHeader title={`Enterprise ${enterprise?.id}`} className="bg-enterprise-50 border-indigo-100"/>
  )
}
