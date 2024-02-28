import {Topology} from "@/components/statistical-unit-hierarchy/topology";
import {createClient} from "@/lib/supabase/server";
import {StatisticalUnitHierarchy} from "@/components/statistical-unit-hierarchy/statistical-unit-hierarchy-types";

interface TopologySlotProps {
  unitId: number;
  unitType: "establishment" | "legal_unit" | "enterprise" | "enterprise_group";
}

export default async function TopologySlot({unitId, unitType}: TopologySlotProps) {
  const {data: hierarchy, error} = await createClient()
    .rpc('statistical_unit_hierarchy', {
      unit_id: unitId,
      unit_type: unitType
    }).returns<StatisticalUnitHierarchy>()

  if (error) {
    console.error(error);
    return null
  }

  if (!hierarchy) {
    console.warn(`no hierarchy found for ${unitType} ${unitId}`);
    return null
  }

  return (
    <Topology hierarchy={hierarchy} unitId={unitId} unitType={unitType}/>
  )
}
