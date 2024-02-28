import {getEstablishmentById} from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getEstablishmentById(id);
  return <HeaderSlot id={id} unit={unit} error={error} className="bg-establishment-100"/>
}
