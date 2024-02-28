import {createClient} from "@/lib/supabase/server";
import {StatisticalUnitHierarchy} from "@/components/statistical-unit-hierarchy/statistical-unit-hierarchy-types";

export type unit_type = 'enterprise' | 'enterprise_group' | 'legal_unit' | 'establishment'

export async function getTopologyByIdAndType(unitId: number, unitType: unit_type) {
  const {data: hierarchy, error} = await createClient()
    .rpc('statistical_unit_hierarchy', {
      unit_id: unitId,
      unit_type: unitType
    }).returns<StatisticalUnitHierarchy>()

  return {hierarchy, error}
}
