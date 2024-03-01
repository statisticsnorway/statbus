import Link from "next/link";
import {cn} from "@/lib/utils";
import {ReactNode} from "react";

export interface StatisticalUnitDetailsLinkProps {
    readonly id: number;
    readonly type: 'enterprise_group' | 'enterprise' | 'legal_unit' | 'establishment';
    readonly children?: ReactNode;
    readonly className?: string;
    readonly sub_path?: string;
}

export function StatisticalUnitDetailsLink({id, type, children, className, sub_path}: StatisticalUnitDetailsLinkProps) {
    const href = {
        enterprise_group: `/enterprise-groups/${id}`,
        enterprise: `/enterprises/${id}`,
        legal_unit: `/legal-units/${id}`,
        establishment: `/establishments/${id}`
    }[type];

    return (
        <Link href={sub_path ? `${href}/${sub_path}` : href} className={cn("font-medium", className)}>
            {children}
        </Link>
    )
}
