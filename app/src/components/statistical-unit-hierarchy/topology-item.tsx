import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {TopologyItemIcon} from "@/components/statistical-unit-hierarchy/topology-item-icon";

export function TopologyItem({type, title, active, children}: {
    readonly type: 'legal_unit' | 'establishment',
    readonly title: string,
    readonly active?: boolean,
    readonly children?: ReactNode
}) {
    return (
        <li className="mb-2">
            <div className={cn("flex items-center gap-2", active ? "underline" : "")}>
                <TopologyItemIcon type={type} active={active}/>
                <span className="flex-1 whitespace-nowrap overflow-hidden overflow-ellipsis">{title}</span>
            </div>
            {children && <ul className="pl-4 pt-4">{children}</ul>}
        </li>
    )
}
