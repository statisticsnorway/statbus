import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {StatisticalUnitDetailsLinkWithSubPath} from "@/components/statistical-unit-details-link-with-sub-path";

interface TopologyItemProps {
    readonly active?: boolean;
    readonly children?: ReactNode;
    readonly type: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
    readonly unit: {
        id: number;
        name?: string;
    }
}

export function TopologyItem({unit: {id, name}, type, active, children}: TopologyItemProps) {
    return (
        <li className="mb-2">
            <div className={cn("flex items-center gap-2", active ? "underline" : "")}>
                <StatisticalUnitIcon type={type}/>
                <StatisticalUnitDetailsLinkWithSubPath
                    id={id}
                    type={type}
                    name={name ?? `${type} ${id}`.toUpperCase()}
                    className="font-normal flex-1 whitespace-nowrap overflow-hidden overflow-ellipsis"
                />
            </div>
            {children && <ul className="pl-4 pt-4">{children}</ul>}
        </li>
    )
}
