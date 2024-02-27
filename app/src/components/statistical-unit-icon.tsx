import {Building, Building2, Store} from "lucide-react";
import {cn} from "@/lib/utils";

interface TopologyItemIconProps {
    type?: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group' | null;
    className?: string;
}

export function StatisticalUnitIcon({type, className}: TopologyItemIconProps) {
    switch (type) {
        case "legal_unit":
            return <Building className={cn("stroke-gray-700 fill-legal_unit-200", className)}/>
        case "establishment":
            return <Store className={cn("stroke-gray-700 fill-establishment-200", className)}/>
        case "enterprise":
            return <Building2 className={cn("stroke-gray-700 fill-enterprise-200", className)}/>
        default:
            return null
    }
}
