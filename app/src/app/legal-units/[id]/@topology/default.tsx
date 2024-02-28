import {Topology} from "@/components/statistical-unit-hierarchy/topology";
import {getTopologyByIdAndType} from "@/app/_requests/hierarchy-requests";

export default async function StatisticalUnitHierarchySlot({params: {id}}: { readonly params: { id: string } }) {
  const unitId = parseInt(id, 10);
  const unitType = "legal_unit";
  const {hierarchy, error} = await getTopologyByIdAndType(unitId, unitType);

  if (error) {
    console.error(error);
    return null
  }

  if (!hierarchy) {
    console.warn(`no hierarchy found for legal unit ${unitId}`);
    return null
  }

  return (
    <Topology hierarchy={hierarchy} unitId={unitId} unitType={unitType}/>
  )
}

