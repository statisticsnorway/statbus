import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {StatisticalUnitDetailsLink} from "@/components/statistical-unit-details-link";

export function TopologyItem({id, type, name, active, children}: {
    readonly type: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group',
    readonly name: string,
    readonly active?: boolean,
    readonly children?: ReactNode
    readonly id: number
}) {


    return (
        <li className="mb-2">
            <div className={cn("flex items-center gap-2", active ? "underline" : "")}>
                <StatisticalUnitIcon type={type}/>
                <StatisticalUnitDetailsLink
                    id={id}
                    type={type}
                    name={name}
                    className="font-normal flex-1 whitespace-nowrap overflow-hidden overflow-ellipsis"
                />
            </div>
            {children && <ul className="pl-4 pt-4">{children}</ul>}
        </li>
    )
}
