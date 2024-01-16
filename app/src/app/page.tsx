import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/components/Search";

export default async function Home() {
  const client = createClient();
  const {data: legalUnits, count, error} = await client
    .from('legal_unit')
    .select('tax_reg_ident, name', {count: 'exact'})
    .gt('id', 0)
    .limit(10);

  const {data: regions} = await client
    .from('region')
    .select()
    .gt('id', 0);

  const {data: activityCategories} = await client
    .from('activity_category_available')
    .select();

  if (error) {
    console.error('⚠️failed to fetch legal units', error);
  }

  return (
    <main className="flex flex-col p-8 md:p-24 space-y-6 max-w-7xl mx-auto">
      <h1 className="font-medium text-lg">Welcome to Statbus!</h1>
      <Search
        regions={regions ?? []}
        activityCategories={activityCategories ?? []}
        legalUnits={legalUnits ?? []}
        count={count ?? 0}
      />
    </main>
  )
}
