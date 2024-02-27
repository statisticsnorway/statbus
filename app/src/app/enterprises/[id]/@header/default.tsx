import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";
import {getEnterpriseById} from "@/app/enterprises/[id]/enterprise-requests";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEnterpriseById(id);
  const name = `Enterprise ${unit?.id}`;
  return (
    <DetailsPageHeader name={name} className="bg-enterprise-50 border-indigo-100"/>
  )
}
