import {createClient} from "@/lib/supabase/server";
import {Topology} from "@/components/statistical-unit-hierarchy/topology";
import {StatisticalUnitHierarchy} from "@/components/statistical-unit-hierarchy/statistical-unit-hierarchy-types";

export default async function StatisticalUnitHierarchySlot({params: {id}}: { readonly params: { id: string } }) {
    const statisticalUnitId = parseInt(id, 10);
    const client = createClient();
    const {data: hierarchy, error} = await client.rpc('statistical_unit_hierarchy', {
        unit_id: statisticalUnitId,
        unit_type: 'enterprise'
    }).returns<StatisticalUnitHierarchy>()

    return error ? null : (
        <Topology hierarchy={hierarchy} unitId={statisticalUnitId} unitType="enterprise"/>
    )
}

