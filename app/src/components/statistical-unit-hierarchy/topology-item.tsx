import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {StatisticalUnitDetailsLinkWithSubPath} from "@/components/statistical-unit-details-link-with-sub-path";
import {Asterisk} from "lucide-react";

interface TopologyItemProps {
  readonly active?: boolean;
  readonly children?: ReactNode;
  readonly type: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
  readonly primary?: boolean;
  readonly unit: {
    id: number;
    name?: string;
  }
}

export function TopologyItem({unit: {id, name}, type, active, primary, children}: TopologyItemProps) {
  return (
    <li className="mb-2">
      <div className={cn("flex items-center gap-2", active ? "underline" : "", primary ? '-ml-6' : null)}>
        {
          primary ? (<Asterisk className="stroke-gray-700 w-4"/>) : null
        }
        <StatisticalUnitIcon type={type} className="w-4"/>
        <StatisticalUnitDetailsLinkWithSubPath
          id={id}
          type={type}
          name={name ?? `${type} ${id}`.toUpperCase()}
          className={cn("font-normal flex-1 whitespace-nowrap overflow-hidden overflow-ellipsis leading-none p-0.5")}
        />
      </div>
      {children && <ul className="pl-6 pt-2">{children}</ul>}
    </li>
  )
}
