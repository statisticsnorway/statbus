import {TopologyItem} from "@/components/statistical-unit-hierarchy/topology-item";

interface TopologyProps {
    readonly hierarchy: StatisticalUnitHierarchy;
    readonly unitId: number;
    readonly unitType: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
}

export function Topology({hierarchy, unitId, unitType}: TopologyProps) {

    const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(lu => lu.primary)

    if (!primaryLegalUnit) {
        return null;
    }

    return (
        <ul className="text-xs">
            <TopologyItem
                type="enterprise"
                unit={primaryLegalUnit}
                active={hierarchy.enterprise.id == unitId && unitType === 'enterprise'}
            >
                {
                    hierarchy.enterprise?.legal_unit.map((legalUnit) => (
                        <TopologyItem
                            key={legalUnit.id}
                            unit={legalUnit}
                            type="legal_unit"
                            active={legalUnit.id === unitId && unitType === 'legal_unit'}
                            primary={legalUnit.primary}
                        >
                            {legalUnit.establishment.map((establishment) =>
                                <TopologyItem
                                    key={establishment.id}
                                    unit={establishment}
                                    active={establishment.id === unitId && unitType === 'establishment'}
                                    type="establishment"
                                    primary={establishment.primary}
                                />
                            )}
                        </TopologyItem>
                    ))
                }
            </TopologyItem>
        </ul>
    )
}

