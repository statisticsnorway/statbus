import { Building, Building2, Store } from "lucide-react";
import { cn } from "@/lib/utils";

interface TopologyItemIconProps {
  type?:
    | "legal_unit"
    | "establishment"
    | "enterprise"
    | "enterprise_group"
    | null;
  className?: string;
}

export function StatisticalUnitIcon({
  type,
  className,
}: TopologyItemIconProps) {
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
          className={cn("fill-establishment-300 stroke-gray-700", className)}
        />
      );
    case "enterprise":
      return (
        <Building2
          className={cn("fill-enterprise-300 stroke-gray-700", className)}
        />
      );
    default:
      return null;
  }
}
