import {Building, Store} from "lucide-react";

interface TopologyItemIconProps {
    type: 'legal_unit' | 'establishment';
    active?: boolean;
}

export function TopologyItemIcon({type, active}: TopologyItemIconProps) {
    const className = active ? 'fill-green-300' : '';
    switch (type) {
        case "legal_unit":
            return <Building size={16} className={className}/>
        case "establishment":
            return <Store size={16} className={className}/>
        default:
            return null
    }
}
