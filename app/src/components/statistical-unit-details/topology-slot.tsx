import { Topology } from "@/components/statistical-unit-hierarchy/topology";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";

interface TopologySlotProps {
  readonly unitId: number;
  readonly unitType:
    | "establishment"
    | "legal_unit"
    | "enterprise"
    | "enterprise_group";
}

export default async function TopologySlot({
  unitId,
  unitType,
}: TopologySlotProps) {
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    unitId,
    unitType
  );

  if (error) {
    console.error(error);
    return null;
  }

  if (!hierarchy) {
    console.warn(`no hierarchy found for ${unitType} ${unitId}`);
    return null;
  }

  return <Topology hierarchy={hierarchy} unitId={unitId} unitType={unitType} />;
}
