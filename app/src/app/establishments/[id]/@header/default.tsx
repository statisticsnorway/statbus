import {getEstablishmentById} from "@/app/establishments/[id]/establishment-requests";
import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEstablishmentById(id);
  return (
    <DetailsPageHeader title={unit?.name} className="bg-establishment-50 border-indigo-100"/>
  )
}
