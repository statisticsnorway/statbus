import {getLegalUnitById} from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({params: {id}}: { readonly params: { id: string } }) {
  const {legalUnit, error} = await getLegalUnitById(id);
  return <HeaderSlot id={id} unit={legalUnit} error={error} className="bg-legal_unit-100 border-legal_unit-200"/>
}

