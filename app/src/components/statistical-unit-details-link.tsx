'use client';
import Link from "next/link";
import {cn} from "@/lib/utils";
import {usePathname} from "next/navigation";

interface StatisticalUnitDetailsLinkProps {
    readonly id: number;
    readonly type: 'enterprise_group' | 'enterprise' | 'legal_unit' | 'establishment';
    readonly name: string;
    readonly className?: string;
}

export function StatisticalUnitDetailsLink({id, type, name, className}: StatisticalUnitDetailsLinkProps) {
    const pathname = usePathname();

    /*
     * When navigating between units, we want to keep the path the same.
     * For example, if we are on /legal-units/1/contact, and we click on an establishment,
     * we want to go to /establishments/2/contact.
     */
    const path = /\d+\/(.+)/.exec(pathname)?.[1] ?? '';

    const href = {
        enterprise_group: `/enterprise-groups/${id}/${path}`,
        enterprise: `/legal-units/${id}/${path}`,
        legal_unit: `/legal-units/${id}/${path}`,
        establishment: `/establishments/${id}/${path}`
    }[type];

    return (
        <Link href={href} className={cn("font-medium", className)}>
            {name}
        </Link>
    )
}
