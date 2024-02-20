import {TopologyItem} from "@/components/statistical-unit-hierarchy/topology-item";
import {StatisticalUnitHierarchy} from "@/components/statistical-unit-hierarchy/statistical-unit-hierarchy-types";

interface TopologyProps {
    readonly hierarchy: StatisticalUnitHierarchy;
    readonly unitId: number;
    readonly unitType: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
}

export function Topology({hierarchy, unitId, unitType}: TopologyProps) {
    return (
        <ul className="text-xs">
            {
                hierarchy?.enterprise.legal_unit.map((legalUnit) => (
                    <TopologyItem
                        key={legalUnit.id}
                        id={legalUnit.id}
                        active={legalUnit.id === unitId && unitType === 'legal_unit'}
                        name={legalUnit.name}
                        type="legal_unit"
                    >
                        {legalUnit.establishment.map((establishment) =>
                            <TopologyItem
                                key={establishment.id}
                                id={establishment.id}
                                active={establishment.id === unitId && unitType === 'establishment'}
                                name={establishment.name}
                                type="establishment"
                            />
                        )}
                    </TopologyItem>
                ))
            }
        </ul>
    )
}

