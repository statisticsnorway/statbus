"use client";

import { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLinkWithSubPath } from "@/components/statistical-unit-details-link-with-sub-path";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Asterisk } from "lucide-react";
import { thousandSeparator } from "@/lib/number-utils";
import { useBaseData } from '@/atoms/hooks';

interface TopologyItemProps {
  readonly active?: boolean;
  readonly children?: ReactNode;
  readonly type:
    | "legal_unit"
    | "establishment"
    | "enterprise"
    | "enterprise_group";
  readonly id: number;
  readonly primary?: boolean;
  readonly unit: LegalUnit | Establishment;
  readonly stats?: StatisticalUnitStats;
}

export function TopologyItem({
  id,
  type,
  unit,
  active,
  primary,
  children,
  stats,
}: TopologyItemProps) {
  const { statDefinitions } = useBaseData();
  const primaryActivity = unit.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const location = unit.location?.find((loc) => loc.type === "physical");
  const isInformal =
    (type === "establishment" && !(unit as Establishment).legal_unit_id) ||
    (type === "enterprise" && "legal_unit_id" in unit);
  return (
    <>
      <StatisticalUnitDetailsLinkWithSubPath
        id={id}
        type={type}
        className={cn("mb-2 block")}
      >
        <Card className="overflow-hidden">
          <CardHeader
            className={cn(
              "flex flex-row items-center justify-between space-y-0 bg-gray-100 px-3 py-1",
              active && "bg-gray-300"
            )}
          >
            <CardTitle className="text-xs font-medium">{unit.name}</CardTitle>
            <div className="flex items-center space-x-1">
              {primary && (
                <div title="This is a primary unit">
                  <Asterisk className="h-4" />
                </div>
              )}

              <StatisticalUnitIcon
                type={type}
                className="w-4"
                hasLegalUnit={!isInformal}
              />
            </div>
          </CardHeader>
          <CardContent className="topology-item-content space-y-3 px-3 pb-2 pt-2">
            <div className="flex justify-between space-x-3 text-center">
              <TopologyItemInfo
                className="flex-1"
                title="Region"
                value={location?.region?.name}
              />
              <TopologyItemInfo
                className="flex-1"
                title="Country"
                value={location?.country?.name}
              />
              {statDefinitions.map((statDefinition) => {
                const statsSum =
                  stats?.stats_summary?.[statDefinition.code]?.sum;
                const stat = unit.stat_for_unit?.find(
                  (s) => s.stat_definition_id === statDefinition.id
                );
                const value =
                  stat?.value_int ??
                  stat?.value_bool ??
                  stat?.value_float ??
                  stat?.value_string;
                const formattedValue =
                  typeof value === "number" ? thousandSeparator(value) : value;
                return (
                  <TopologyItemInfo
                    key={statDefinition.id}
                    className="flex-1"
                    title={statDefinition.name!}
                    value={type !== "enterprise" && formattedValue}
                    sum={thousandSeparator(statsSum)}
                  />
                );
              })}
            </div>
            <TopologyItemInfo
              title="Primary Activity"
              value={
                primaryActivity
                  ? `${primaryActivity?.code} - ${primaryActivity?.name}`
                  : undefined
              }
            />
          </CardContent>
        </Card>
      </StatisticalUnitDetailsLinkWithSubPath>
      <ul className="pl-4">{children}</ul>
    </>
  );
}

interface TopologyItemInfoProps {
  title: string;
  value?: string | number | boolean | null;
  fallbackValue?: string;
  className?: string;
  sum?: string | number | boolean | null;
}

const TopologyItemInfo = ({
  title,
  value,
  fallbackValue = "-",
  className,
  sum,
}: TopologyItemInfoProps) => (
  <div className={cn("flex flex-col space-y-0 text-left", className)}>
    <span className="text-xs font-medium uppercase text-gray-500">{title}</span>
    <span className="text-sm">{value ?? fallbackValue}</span>
    {sum && (
      <div className="inline-flex items-center font-semibold">
        <span className="text-xs mr-1">&#8721;</span>
        <span className="text-sm">{sum}</span>
      </div>
    )}
  </div>
);
