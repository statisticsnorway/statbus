import { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLinkWithSubPath } from "@/components/statistical-unit-details-link-with-sub-path";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Asterisk } from "lucide-react";
import { thousandSeparator } from "@/lib/number-utils";

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
}

export function TopologyItem({
  id,
  type,
  unit,
  active,
  primary,
  children,
}: TopologyItemProps) {
  const activity = unit.activity?.[0];
  const location = unit.location?.[0];
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
              <StatisticalUnitIcon type={type} className="w-4" />
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
              <TopologyItemInfo
                className="flex-1"
                title="Employees"
                value={thousandSeparator(unit.stat_for_unit?.[0].employees)}
              />
              <TopologyItemInfo
                className="flex-1"
                title="Turnover"
                value={thousandSeparator(unit.stat_for_unit?.[1]?.turnover)}
              />
            </div>
            <TopologyItemInfo
              title="Activity"
              value={activity?.activity_category?.name}
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
  value?: string | number;
  fallbackValue?: string;
  className?: string;
}

const TopologyItemInfo = ({
  title,
  value,
  fallbackValue = "-",
  className,
}: TopologyItemInfoProps) => (
  <div className={cn("flex flex-col space-y-0 text-left", className)}>
    <span className="text-xs font-medium uppercase text-gray-500">{title}</span>
    <span className="text-sm">{value ?? fallbackValue}</span>
  </div>
);
