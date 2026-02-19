"use client";
import { Topology } from "@/components/statistical-unit-hierarchy/topology";
import { logger } from "@/lib/client-logger";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "./unit-not-found";

interface TopologySlotProps {
  readonly unitId: string;
  readonly unitType:
    | "establishment"
    | "legal_unit"
    | "enterprise"
    | "power_group";
}

export default function TopologySlot({ unitId, unitType }: TopologySlotProps) {
  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    unitId,
    unitType
  );
  if (error) {
    logger.error(
      "TopologySlot",
      "failed to fetch statistical unit hierarchy",
      { error }
    );
    return null;
  }

  if (!hierarchy) {
    if (!isLoading) {
      logger.warn("TopologySlot", `no hierarchy found for ${unitType} ${unitId}`);
      return <UnitNotFound />;
    }
    return null;
  }

  return <Topology hierarchy={hierarchy} unitId={unitId} unitType={unitType} />;
}
