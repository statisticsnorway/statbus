import {TopologyItem} from "@/components/statistical-unit-hierarchy/topology-item";
import {StatisticalUnitHierarchy} from "@/components/statistical-unit-hierarchy/statistical-unit-hierarchy-types";

interface TopologyProps {
  readonly hierarchy: StatisticalUnitHierarchy;
  readonly unitId: number;
  readonly unitType: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
}

export function Topology({hierarchy, unitId, unitType}: TopologyProps) {
  if (hierarchy.enterprise === null) {
    return null;
  }

  return (
    <ul className="text-xs">
      <TopologyItem type="enterprise" unit={hierarchy?.enterprise}>
        {
          hierarchy?.enterprise?.legal_unit.map((legalUnit) => (
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

