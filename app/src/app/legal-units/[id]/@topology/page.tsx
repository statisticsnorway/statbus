import {Building, Store} from "lucide-react";
import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {createClient} from "@/lib/supabase/server";
import {StatisticalUnitHierarchy} from "@/app/legal-units/[id]/statistical-unit-hierarchy-types";

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

function Topology({hierarchy, statisticalUnitId}: { hierarchy: StatisticalUnitHierarchy, statisticalUnitId: number}) {
    return (
        <ul className="text-xs">
            {
                hierarchy?.enterprise.legal_unit.map((lu) => (
                    <TopologyItem
                        key={lu.id}
                        active={lu.id === statisticalUnitId}
                        title={lu.name}
                        type="legal_unit"
                    >
                        {lu.establishment.map((e) =>
                            <TopologyItem
                                key={e.id}
                                active={false}
                                title={e.name}
                                type="establishment"
                            />
                        )}
                    </TopologyItem>
                ))
            }
        </ul>
    )
}

function TopologyItemIcon({type, active}: { type: 'legal_unit' | 'establishment', active?: boolean }) {
    const className = active ? 'fill-green-300' : '';
    switch (type) {
        case "legal_unit":
            return <Building size={16} className={className}/>
        case "establishment":
            return <Store size={16} className={className}/>
        default:
            return null
    }
}

function TopologyItem({type, title, active, children}: {
    readonly type: 'legal_unit' | 'establishment',
    readonly title: string,
    readonly active?: boolean,
    readonly children?: ReactNode
}) {
    return (
        <li className="mb-2">
            <div className={cn("flex items-center gap-2", active ? "underline" : "")}>
                <TopologyItemIcon type={type} active={active}/>
                <span className="flex-1 whitespace-nowrap overflow-hidden overflow-ellipsis">{title}</span>
            </div>
            {children && <ul className="pl-4 pt-4">{children}</ul>}
        </li>
    )
}
