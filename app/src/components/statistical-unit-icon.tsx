import {Building, Building2, Store} from "lucide-react";

interface TopologyItemIconProps {
    type?: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group' | null;
    size?: number;
}

export function StatisticalUnitIcon({type, size = 16}: TopologyItemIconProps) {
    switch (type) {
        case "legal_unit":
            return <Building size={size} className="stroke-green-700"/>
        case "establishment":
            return <Store size={size} className="stroke-blue-500"/>
        case "enterprise":
            return <Building2 size={size}/>
        default:
            return null
    }
}
