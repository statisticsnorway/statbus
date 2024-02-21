import {getLegalUnitById} from "@/app/legal-units/[id]/legal-unit-requests";
import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id);
  return (
    <DetailsPageHeader name={unit?.name}/>
  )
}

