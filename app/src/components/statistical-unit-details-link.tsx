import Link from "next/link";
import {cn} from "@/lib/utils";

export interface StatisticalUnitDetailsLinkProps {
    readonly id: number;
    readonly type: 'enterprise_group' | 'enterprise' | 'legal_unit' | 'establishment';
    readonly name: string;
    readonly className?: string;
    readonly sub_path?: string;
}

export function StatisticalUnitDetailsLink({id, type, name, className, sub_path}: StatisticalUnitDetailsLinkProps) {
    const href = {
        enterprise_group: `/enterprise-groups/${id}`,
        enterprise: `/enterprises/${id}`,
        legal_unit: `/legal-units/${id}`,
        establishment: `/establishments/${id}`
    }[type];

    return (
        <Link href={sub_path ? `${href}/${sub_path}` : href} className={cn("font-medium", className)}>
            {name}
        </Link>
    )
}
