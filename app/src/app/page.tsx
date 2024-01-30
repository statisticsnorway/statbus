import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/components/Search";

export default async function Home() {
  const client = createClient();
  const {data: statisticalUnits, count, error: legalUnitsError} = await client
    .from('statistical_unit')
    .select('name, primary_activity_category_id, legal_unit_id, physical_region_id', {count: 'exact'})
    .order('enterprise_id', {ascending: false})
    .limit(10);

  const {data: regions, error: regionsError} = await client
    .from('region')
    .select()

  const {data: activityCategories, error: activityCategoriesError} = await client
    .from('activity_category_available')
    .select();

  const {data: statisticalVariables} = await client
    .from('stat_definition')
    .select()
    .order('priority', {ascending: true});

  if (legalUnitsError) {
    console.error('⚠️failed to fetch legal units', legalUnitsError);
  }

  if (regionsError) {
    console.error('⚠️failed to fetch regions', regionsError);
  }

  if (activityCategoriesError) {
    console.error('⚠️failed to fetch activity categories', activityCategoriesError);
  }

  return (
    <main className="flex flex-col py-8 px-2 md:py-24 space-y-6 max-w-5xl mx-auto">
      <h1 className="font-medium text-lg">Welcome to Statbus!</h1>
      <Search
        regions={regions ?? []}
        activityCategories={activityCategories ?? []}
        statisticalVariables={statisticalVariables ?? []}
        initialSearchResult={{statisticalUnits: statisticalUnits ?? [], count: count ?? 0}}
      />
    </main>
  )
}
