import Link from "next/link";
import {cn} from "@/lib/utils";

interface StatisticalUnitDetailsLinkProps {
    readonly id: number;
    readonly type: 'enterprise_group' | 'enterprise' | 'legal_unit' | 'establishment';
    readonly name: string;
    readonly className?: string;
}

export function StatisticalUnitDetailsLink({id, type, name, className}: StatisticalUnitDetailsLinkProps) {

    // TODO: Update enterprise link when enterprise details page is implemented
    const href = {
        enterprise_group: `/enterprise-groups/${id}`,
        enterprise: `/legal-units/${id}`,
        legal_unit: `/legal-units/${id}`,
        establishment: `/establishments/${id}`
    }[type];

    return (
        <Link href={href} className={cn("font-medium", className)}>
            {name}
        </Link>
    )
}
