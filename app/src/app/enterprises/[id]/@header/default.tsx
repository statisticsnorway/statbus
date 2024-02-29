import {getStatisticalUnitHierarchy} from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({params: {id}}: { readonly params: { id: string } }) {
  const {hierarchy, error} = await getStatisticalUnitHierarchy(parseInt(id, 10), 'enterprise')
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit.find(lu => lu.primary)
  return <HeaderSlot id={id} unit={primaryLegalUnit} error={error} className="bg-enterprise-100 border-enterprise-200"/>
}
