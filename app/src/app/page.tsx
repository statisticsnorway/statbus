import {Metadata} from "next";
import {Card, CardContent, CardHeader, CardTitle} from "@/components/ui/card";
import {AlertTriangle, BarChart3, Building, Globe2, ScrollText, Settings} from "lucide-react";
import {createClient} from "@/lib/supabase/server";
import {ReactNode} from "react";
import {cn} from "@/lib/utils";
import Link from "next/link";

export const metadata: Metadata = {
  title: "StatBus | Dashboard"
}

export default async function Dashboard() {
  const client = createClient();

  const unitsPromise = client
    .from('statistical_unit')
    .select('name', {count: 'exact'})
    .limit(0);

  const unitsMissingRegionPromise = client
    .from('statistical_unit')
    .select('name', {count: 'exact'})
    .is('physical_region_path', null)
    .limit(0)

  const unitsMissingActivityCategoryPromise = client
    .from('statistical_unit')
    .select('name', {count: 'exact'})
    .is('primary_activity_category_path', null)
    .limit(0)

  const regionsPromise = client
    .from('region')
    .select('name', {count: 'exact'})
    .limit(0)

  const settingsPromise = client
    .from('settings')
    .select('activity_category_standard(id,name)')
    .limit(1)

  const statDefinitionPromise = client
    .from('stat_definition')
    .select('id', {count: 'exact'})
    .limit(0)

  const customActivityCategoryCodesPromise = await client
    .from('activity_category_available_custom')
    .select('path', {count: 'exact'})
    .limit(0)

  const [
    {count: unitsCount, error: unitsError},
    {count: unitsMissingRegionCount, error: unitsMissingRegionError},
    {count: unitsMissingActivityCategoryCount, error: unitsMissingActivityCategoryError},
    {count: regionsCount, error: regionsError},
    {count: statisticalVariablesCount, error: statisticalVariablesError},
    {count: customActivityCategoryCodesCount, error: customActivityCategoryCodesError},
    {data: settings, error: settingsError}
  ] = await Promise.all([
    unitsPromise,
    unitsMissingRegionPromise,
    unitsMissingActivityCategoryPromise,
    regionsPromise,
    statDefinitionPromise,
    customActivityCategoryCodesPromise,
    settingsPromise
  ]);


  return (
    <main className="flex flex-col py-8 px-2 md:py-24 max-w-5xl mx-auto">
      <h1 className="font-medium text-xl text-center mb-12">StatBus Status Dashboard</h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <Link href="/search">
          <DashboardCard
            title="Statistical Units"
            icon={<Building className="h-4"/>}
            text={unitsCount?.toString() ?? '-'}
            failed={!!unitsError}
          />
        </Link>

        <DashboardCard
          title="Regions"
          icon={<Globe2 className="h-4"/>}
          text={regionsCount?.toString() ?? '-'}
          failed={!!regionsError}
        />

        <Link href="/getting-started/activity-standard">
          <DashboardCard
            title="Activity Category Standard"
            icon={<ScrollText className="h-4"/>}
            text={settings?.[0]?.activity_category_standard?.name ?? '-'}
            failed={!!settingsError}
          />
        </Link>

        <DashboardCard
          title="Statistical Variables"
          icon={<BarChart3 className="h-4"/>}
          text={statisticalVariablesCount?.toString() ?? '-'}
          failed={!!statisticalVariablesError}
        />

        <Link href="/getting-started/upload-custom-activity-standard-codes">
          <DashboardCard
            title="Custom Activity Category Codes"
            icon={<Settings className="h-4"/>}
            text={customActivityCategoryCodesCount?.toString() ?? '-'}
            failed={!!customActivityCategoryCodesError}
          />
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&physical_region_path=">
          <DashboardCard
            title="Units Missing Region"
            icon={<AlertTriangle className="h-4"/>}
            text={unitsMissingRegionCount?.toString() ?? '-'}
            failed={unitsMissingRegionCount !== null && unitsMissingRegionCount > 0 || !!unitsMissingRegionError}
          />
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&primary_activity_category_path=">
          <DashboardCard
            title="Units Missing Activity Category"
            icon={<AlertTriangle className="h-4"/>}
            text={unitsMissingActivityCategoryCount?.toString() ?? '-'}
            failed={unitsMissingActivityCategoryCount !== null && unitsMissingActivityCategoryCount > 0 || !!unitsMissingActivityCategoryError}
          />
        </Link>
      </div>
    </main>
  )
}

const DashboardCard = ({title, icon, text, failed}: {
  readonly title: string,
  readonly icon: ReactNode,
  readonly text: string,
  readonly failed: boolean
}) => {
  return (
    <Card className="overflow-hidden">
      <CardHeader
        className={cn("flex flex-row items-center justify-between space-y-0 py-2 px-3 bg-gray-100", failed ? "bg-orange-100 border-orange-400" : "")}
      >
        <CardTitle className="text-xs font-medium">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent className="py-3 px-3 space-y-3">
        <div className="text-xl font-semibold text-right">{text}</div>
      </CardContent>
    </Card>
  )
}
