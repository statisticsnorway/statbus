import {Metadata} from "next";
import {Card, CardContent, CardHeader, CardTitle} from "@/components/ui/card";
import {BarChart3, Building, Globe2, ScrollText, Settings} from "lucide-react";
import {createClient} from "@/lib/supabase/server";
import {ReactNode} from "react";
import {cn} from "@/lib/utils";

export const metadata: Metadata = {
  title: "StatBus | Dashboard"
}

export default async function Dashboard() {
  const client = createClient();

  const statisticalUnitPromise = client
    .from('statistical_unit')
    .select('name', {count: 'exact'})
    .limit(0);

  const regionPromise = client
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
    {count: statisticalUnitsCount, error: statisticalUnitsError},
    {count: regionsCount, error: regionsError},
    {count: statisticalVariablesCount, error: statisticalVariablesError},
    {count: customActivityCategoryCodesCount, error: customActivityCategoryCodesError},
    {data: settings, error: settingsError}
  ] = await Promise.all([
    statisticalUnitPromise,
    regionPromise,
    statDefinitionPromise,
    customActivityCategoryCodesPromise,
    settingsPromise
  ]);


  return (
    <main className="flex flex-col py-8 px-2 md:py-24 max-w-5xl mx-auto">
      <h1 className="font-medium text-xl text-center mb-12">StatBus Dashboard</h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <DashboardCard
          title="Statistical Units"
          icon={<Building size={18}/>}
          text={statisticalUnitsCount?.toString() ?? '-'}
          failed={!!statisticalUnitsError}
        />

        <DashboardCard
          title="Regions"
          icon={<Globe2 size={18}/>}
          text={regionsCount?.toString() ?? '-'}
          failed={!!regionsError}
        />

        <DashboardCard
          title="Activity Category Standard"
          icon={<ScrollText size={18}/>}
          text={settings?.[0]?.activity_category_standard?.name ?? '-'}
          failed={!!settingsError}
        />

        <DashboardCard
          title="Statistical Variables"
          icon={<BarChart3 size={18}/>}
          text={statisticalVariablesCount?.toString() ?? '-'}
          failed={!!statisticalVariablesError}
        />

        <DashboardCard
          title="Custom Activity Category Codes"
          icon={<Settings size={18}/>}
          text={customActivityCategoryCodesCount?.toString() ?? '-'}
          failed={!!customActivityCategoryCodesError}
        />

        <DashboardCardPlaceholder/>
      </div>
    </main>
  )
}

const DashboardCardPlaceholder = () => (
  <div className="col-span-1 bg-gray-50 text-center p-12 text-gray-500 rounded"></div>
)

const DashboardCard = ({title, icon, text, failed}: {
  title: string,
  icon: ReactNode,
  text: string,
  failed: boolean
}) => {
  return (
    <Card className={cn("", failed ? "bg-red-100" : "")}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">
          {title}
        </CardTitle>
        {icon}
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{text}</div>
      </CardContent>
    </Card>
  )
}
