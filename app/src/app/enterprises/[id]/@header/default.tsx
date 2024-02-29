import {getEnterpriseById} from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({params: {id}}: { readonly params: { id: string } }) {
  const {error} = await getEnterpriseById(id)
  const unit = {name: `Enterprise ${id}`};
  return <HeaderSlot id={id} unit={unit} error={error} className="bg-enterprise-100 border-enterprise-200"/>
}
