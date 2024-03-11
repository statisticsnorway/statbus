'use client';
import {TopologyItem} from "@/components/statistical-unit-hierarchy/topology-item";
import {cn} from "@/lib/utils";
import {Switch} from "@/components/ui/switch";
import {useState} from "react";
import {Label} from "@/components/ui/label";

interface TopologyProps {
    readonly hierarchy: StatisticalUnitHierarchy;
    readonly unitId: number;
    readonly unitType: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
}

export function Topology({hierarchy, unitId, unitType}: TopologyProps) {

    const [compact, setCompact] = useState(true)
    const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(lu => lu.primary)

    if (!primaryLegalUnit) {
        return null;
    }

    return (
        <>
            <div className="flex items-center space-x-2 justify-end mb-3">
                <Label htmlFor="compact-mode" className="text-gray-800 uppercase text-xs">View details</Label>
                <Switch id="compact-mode" checked={!compact} onCheckedChange={() => setCompact(v => !v)}/>
            </div>
            <ul className={cn('hierarchy', compact && '[&_.topology-item-content]:hidden')}>
                <TopologyItem
                    type="enterprise"
                    id={hierarchy.enterprise.id}
                    unit={primaryLegalUnit}
                    active={hierarchy.enterprise.id == unitId && unitType === 'enterprise'}
                >
                    {
                        hierarchy.enterprise.legal_unit.map((legalUnit) => (
                            <TopologyItem
                                key={legalUnit.id}
                                type="legal_unit"
                                id={legalUnit.id}
                                unit={legalUnit}
                                active={legalUnit.id === unitId && unitType === 'legal_unit'}
                                primary={legalUnit.primary}
                            >
                                {legalUnit.establishment?.map((establishment) =>
                                    <TopologyItem
                                        key={establishment.id}
                                        type="establishment"
                                        id={establishment.id}
                                        unit={establishment}
                                        active={establishment.id === unitId && unitType === 'establishment'}
                                        primary={establishment.primary}
                                    />
                                )}
                            </TopologyItem>
                        ))
                    }
                </TopologyItem>
            </ul>
        </>
    )
}

