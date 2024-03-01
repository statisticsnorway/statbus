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
    const primaryActivityCategory = unit.activity?.[0]
    const primaryLocation = unit.location?.[0];
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
                    <CardContent className="py-5 px-5 space-y-8">
                        <div className="flex justify-between text-center">
                            <div className="space-y-1.5 flex flex-col">
                                <label className="text-xs uppercase font-medium leading-none text-gray-500">Employees</label>
                                <span className="text-sm text-muted-foreground text-center">{unit.stat_for_unit?.[0].employees ?? '-'}</span>
                            </div>
                            <div className="space-y-1.5 flex flex-col">
                                <label className="text-xs uppercase font-medium leading-none text-gray-500">Region</label>
                                <span className="text-sm text-muted-foreground">{primaryLocation?.region?.name ?? '-'}</span>
                            </div>
                            <div className="space-y-1.5 flex flex-col">
                                <label
                                    className="text-xs uppercase font-medium leading-none text-gray-500">Country</label>
                                <span className="text-sm text-muted-foreground">{primaryLocation?.country?.name ?? '-'}</span>
                            </div>
                        </div>
                        {
                            primaryActivityCategory && (
                                <div className="space-y-1.5 flex flex-col">
                                    <label className="text-xs uppercase font-medium leading-none text-gray-500">Category</label>
                                    <span className="text-sm text-muted-foreground">{primaryActivityCategory.activity_category.name ?? '-'}</span>
                                </div>
                            )
                        }
                    </CardContent>
                </Card>
            </StatisticalUnitDetailsLinkWithSubPath>
            {children && <ul>{children}</ul>}
        </>
    )
}
