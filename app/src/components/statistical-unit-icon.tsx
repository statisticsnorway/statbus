import {Building, Building2, Store} from "lucide-react";

interface TopologyItemIconProps {
    type?: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group' | null;
    size?: number;
}

export function StatisticalUnitIcon({type, size = 16}: TopologyItemIconProps) {
    switch (type) {
        case "legal_unit":
            return <Building size={size} className="stroke-gray-700 fill-legal_unit-200"/>
        case "establishment":
            return <Store size={size} className="stroke-gray-700 fill-establishment-200"/>
        case "enterprise":
            return <Building2 size={size} className="stroke-gray-700 fill-enterprise-200"/>
        default:
            return null
    }
}
