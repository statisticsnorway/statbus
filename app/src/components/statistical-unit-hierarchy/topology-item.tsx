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
    const activity = unit.activity?.[0]
    const location = unit.location?.[0];
    return (
        <>
            <StatisticalUnitDetailsLinkWithSubPath
                id={unit.id}
                type={type}
                className={cn("mb-2 block")}
            >
                <Card className="overflow-hidden">
                    <CardHeader
                        className={cn("flex flex-row items-center justify-between space-y-0 py-1 px-3 bg-gray-100", active && 'bg-gray-300')}
                    >
                        <CardTitle className="text-xs font-medium">{unit.name}</CardTitle>
                        <div className="flex items-center space-x-1">
                            {primary && <div title="This is a primary unit"><Asterisk className="h-4"/></div>}
                            <StatisticalUnitIcon type={type} className="w-4"/>
                        </div>
                    </CardHeader>
                    <CardContent className="topology-item-content pb-2 pt-2 px-3 space-y-3">
                        <div className="flex justify-between text-center">
                            <TopologyItemInfo title="Region" value={location?.region?.name}/>
                            <TopologyItemInfo title="Country" value={location?.country?.name}/>
                            <TopologyItemInfo title="Employees" value={unit.stat_for_unit?.[0].employees}/>
                        </div>
                        <TopologyItemInfo title="Activity" value={activity?.activity_category?.name}/>
                    </CardContent>
                </Card>
            </StatisticalUnitDetailsLinkWithSubPath>
            <ul>{children}</ul>
        </>
    )
}

interface TopologyItemInfoProps {
    title: string;
    value?: string | number;
    fallbackValue?: string;
    className?: string;
}

const TopologyItemInfo = ({title, value, fallbackValue = '-', className}: TopologyItemInfoProps) => (
    <div className={cn("space-y-0 flex flex-col text-left", className)}>
        <span className="text-xs uppercase font-medium text-gray-500">{title}</span>
        <span className="text-sm">{value ?? fallbackValue}</span>
    </div>
)
