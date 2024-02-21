import {getEstablishmentById} from "@/app/establishments/[id]/establishment-requests";
import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEstablishmentById(id);
  return (
    <DetailsPageHeader name={unit?.name} className="bg-indigo-50 border-indigo-100"/>
  )
}
