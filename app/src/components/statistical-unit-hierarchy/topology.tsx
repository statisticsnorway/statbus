import {StatisticalUnitHierarchy} from "@/app/legal-units/[id]/statistical-unit-hierarchy-types";
import {TopologyItem} from "@/components/statistical-unit-hierarchy/topology-item";

interface TopologyProps {
    readonly hierarchy: StatisticalUnitHierarchy;
    readonly statisticalUnitId: number;
}

export function Topology({hierarchy, statisticalUnitId}: TopologyProps) {
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

