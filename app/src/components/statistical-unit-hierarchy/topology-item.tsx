import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {StatisticalUnitDetailsLinkWithSubPath} from "@/components/statistical-unit-details-link-with-sub-path";
import {Card, CardContent, CardHeader, CardTitle} from "@/components/ui/card";
import {Asterisk} from "lucide-react";

interface TopologyItemProps {
    readonly active?: boolean;
    readonly children?: ReactNode;
    readonly type: 'legal_unit' | 'establishment' | 'enterprise' | 'enterprise_group';
    readonly primary?: boolean;
    readonly unit: LegalUnit | Establishment;
}

export function TopologyItem({unit, type, active, primary, children}: TopologyItemProps) {
    return (
        <>
            <StatisticalUnitDetailsLinkWithSubPath
                id={unit.id}
                type={type}
                className={cn("mb-4 block")}
            >
                <Card className="overflow-hidden">
                    <CardHeader
                        className={cn("flex flex-row items-center justify-between space-y-0 py-3 px-5 bg-gray-100", active && 'bg-amber-200')}>
                        <CardTitle className="text-xs text-gray-700 font-medium flex items-center space-x-2">
                            <span className="leading-none">{unit.name}</span>
                        </CardTitle>
                        <div className="flex items-center space-x-1">
                            {primary && <div title="This is a primary unit"><Asterisk className="h-4"/></div>}
                            <StatisticalUnitIcon type={type} className="w-4"/>
                        </div>
                    </CardHeader>
                    <CardContent className="py-5 px-5">
                        <div className="space-y-1 flex flex-col">
                            <label className="text-xs uppercase font-medium leading-none text-gray-500">Tax ID</label>
                            <span className="text-sm text-muted-foreground">{unit.tax_reg_ident}</span>
                        </div>
                    </CardContent>
                </Card>
            </StatisticalUnitDetailsLinkWithSubPath>
            {children && <ul>{children}</ul>}
        </>
    )
}
