import { Topology } from "@/components/statistical-unit-hierarchy/topology";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";

import { createServerLogger } from "@/lib/server-logger";

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
  const logger = await createServerLogger();
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    unitId,
    unitType
  );

  if (error) {
    logger.error(error, "failed to fetch statistical unit hierarchy");
    return null;
  }

  if (!hierarchy) {
    logger.warn(`no hierarchy found for ${unitType} ${unitId}`);
    return null;
  }

  return <Topology hierarchy={hierarchy} unitId={unitId} unitType={unitType} />;
}
