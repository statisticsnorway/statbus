import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/components/Search";

export default async function Home() {
  const client = createClient();
  const {data: legalUnits, count, error: legalUnitsError} = await client
    .from('legal_unit')
    .select('tax_reg_ident, name', {count: 'exact'})
    .order('id', {ascending: false})
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
    <main className="flex flex-col p-8 md:p-24 space-y-6 max-w-7xl mx-auto">
      <h1 className="font-medium text-lg">Welcome to Statbus!</h1>
      <Search
        regions={regions ?? []}
        activityCategories={activityCategories ?? []}
        statisticalVariables={statisticalVariables ?? []}
        initialSearchResult={{legalUnits: legalUnits ?? [], count: count ?? 0}}
      />
    </main>
  )
}