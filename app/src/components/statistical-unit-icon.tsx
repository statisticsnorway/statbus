import { Building, Building2, Store, Crown } from "lucide-react";
import { cn } from "@/lib/utils";

interface TopologyItemIconProps {
  type?:
    | "legal_unit"
    | "establishment"
    | "enterprise"
    | "power_group"
    | null;
  className?: string;
  hasLegalUnit?: boolean;
}

export function StatisticalUnitIcon({
  type,
  className,
  hasLegalUnit = true,
}: TopologyItemIconProps) {
  const isInformal =
    (type === "establishment" || type === "enterprise") && !hasLegalUnit;

  switch (type) {
    case "legal_unit":
      return (
        <Building
          className={cn("fill-legal_unit-300 stroke-gray-700", className)}
        />
      );
    case "establishment":
      return (
        <Store
          className={cn(
            `stroke-gray-700 ${
              isInformal ? "fill-informal-50" : "fill-establishment-300"
            }`,
            className
          )}
        />
      );
    case "enterprise":
      return (
        <Building2
          className={cn(
            `stroke-gray-700 ${
              isInformal ? "fill-informal-500" : "fill-enterprise-300"
            }`,
            className
          )}
        />
      );
    case "power_group":
      return (
        <Crown
          className={cn("fill-power_group-300 stroke-gray-700", className)}
        />
      );
    default:
      return null;
  }
}
