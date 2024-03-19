"use client";
import { TopologyItem } from "@/components/statistical-unit-hierarchy/topology-item";
import { cn } from "@/lib/utils";
import { Switch } from "@/components/ui/switch";
import { useState } from "react";
import { Label } from "@/components/ui/label";

interface TopologyProps {
  readonly hierarchy: StatisticalUnitHierarchy;
  readonly unitId: number;
  readonly unitType:
    | "legal_unit"
    | "establishment"
    | "enterprise"
    | "enterprise_group";
}

export function Topology({ hierarchy, unitId, unitType }: TopologyProps) {
  const [compact, setCompact] = useState(true);
  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary
  );

  if (!primaryLegalUnit) {
    return null;
  }

  return (
    <>
      <div className="mb-3 flex items-center justify-end space-x-2">
        <Label
          htmlFor="compact-mode"
          className="text-xs uppercase text-gray-800"
        >
          View details
        </Label>
        <Switch
          id="compact-mode"
          checked={!compact}
          onCheckedChange={() => setCompact((v) => !v)}
        />
      </div>
      <ul
        className={cn(
          "hierarchy",
          compact && "[&_.topology-item-content]:hidden"
        )}
      >
        <TopologyItem
          type="enterprise"
          id={hierarchy.enterprise.id}
          unit={primaryLegalUnit}
          active={
            hierarchy.enterprise.id == unitId && unitType === "enterprise"
          }
        >
          {hierarchy.enterprise.legal_unit.map((legalUnit) => (
            <TopologyItem
              key={legalUnit.id}
              type="legal_unit"
              id={legalUnit.id}
              unit={legalUnit}
              active={legalUnit.id === unitId && unitType === "legal_unit"}
              primary={legalUnit.primary_for_enterprise}
            >
              {legalUnit.establishment?.map((establishment) => (
                <TopologyItem
                  key={establishment.id}
                  type="establishment"
                  id={establishment.id}
                  unit={establishment}
                  active={
                    establishment.id === unitId && unitType === "establishment"
                  }
                  primary={establishment.primary_for_legal_unit}
                />
              ))}
            </TopologyItem>
          ))}
        </TopologyItem>
      </ul>
    </>
  );
}
