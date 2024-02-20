import {createClient} from "@/lib/supabase/server";
import {StatisticalUnitHierarchy} from "@/app/legal-units/[id]/statistical-unit-hierarchy-types";
import {Topology} from "@/components/statistical-unit-hierarchy/topology";

export default async function StatisticalUnitHierarchySlot({params: {id}}: { readonly params: { id: string } }) {
    const statisticalUnitId = parseInt(id, 10);
    const client = createClient();
    const {data: hierarchy, error} = await client.rpc('statistical_unit_hierarchy', {
        unit_id: statisticalUnitId,
        unit_type: 'legal_unit'
    }).returns<StatisticalUnitHierarchy>()

    if (error) {
        console.error('⚠️failed to fetch statistical unit hierarchy data', error);
        return null
    }

    return (
        <Topology hierarchy={hierarchy} statisticalUnitId={statisticalUnitId} />
    )
}

