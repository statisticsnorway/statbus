"use client";
import { TopologyItem } from "@/components/statistical-unit-hierarchy/topology-item";
import { cn } from "@/lib/utils";
import { Switch } from "@/components/ui/switch";
import { useEffect, useState } from "react";
import { Label } from "@/components/ui/label";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import useHierarchyStats from "./use-hierarchy-stats";

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
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const details = searchParams?.get("details");
  const [compact, setCompact] = useState(!details);

  useEffect(() => {
    setCompact(!details);
  }, [details]);

  const { hierarchyStats } = useHierarchyStats(unitId, unitType, compact);

  const handleCompactChange = () => {
    const params = new URLSearchParams(searchParams?.toString() ?? "");
    if (compact) {
      params.set("details", "true");
    } else {
      params.delete("details");
    }
    router.replace(`${pathname}?${params}`);
    setCompact(!compact);
  };

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  if (!primaryUnit) {
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
          onCheckedChange={handleCompactChange}
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
          unit={primaryUnit}
          active={
            hierarchy.enterprise.id == unitId && unitType === "enterprise"
          }
          stats={hierarchyStats?.find(
            (stat) =>
              stat.unit_id === hierarchy.enterprise.id &&
              stat.unit_type === "enterprise"
          )}
        >
          {primaryLegalUnit &&
            hierarchy.enterprise.legal_unit.map((legalUnit) => (
              <TopologyItem
                key={legalUnit.id}
                type="legal_unit"
                id={legalUnit.id}
                unit={legalUnit}
                active={legalUnit.id === unitId && unitType === "legal_unit"}
                primary={legalUnit.primary_for_enterprise}
                stats={hierarchyStats?.find(
                  (stat) =>
                    stat.unit_id === legalUnit.id &&
                    stat.unit_type === "legal_unit"
                )}
              >
                {legalUnit.establishment?.map((establishment) => (
                  <TopologyItem
                    key={establishment.id}
                    type="establishment"
                    id={establishment.id}
                    unit={establishment}
                    active={
                      establishment.id === unitId &&
                      unitType === "establishment"
                    }
                    primary={establishment.primary_for_legal_unit}
                  />
                ))}
              </TopologyItem>
            ))}
          {primaryEstablishment &&
            hierarchy.enterprise.establishment?.map((establishment) => (
              <TopologyItem
                key={establishment.id}
                type="establishment"
                id={establishment.id}
                unit={establishment}
                active={
                  establishment.id === unitId && unitType === "establishment"
                }
                primary={establishment.primary_for_enterprise}
              />
            ))}
        </TopologyItem>
      </ul>
    </>
  );
}
