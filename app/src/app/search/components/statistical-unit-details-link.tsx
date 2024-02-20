import Link from "next/link";

interface StatisticalUnitDetailsLinkProps {
    readonly id: number;
    readonly type: 'enterprise_group' | 'enterprise' | 'legal_unit' | 'establishment';
    readonly name: string;
}

export function StatisticalUnitDetailsLink({id, type, name}: StatisticalUnitDetailsLinkProps) {
    const typeToHrefMapping = {
        enterprise_group: `/enterprise-groups/${id}`,
        enterprise: `/enterprises/${id}`,
        legal_unit: `/legal-units/${id}`,
        establishment: `/establishments/${id}`
    };

    return (
        <Link href={typeToHrefMapping[type]} className="font-medium">
            {name}
        </Link>
    )
}
