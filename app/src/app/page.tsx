import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/Search";

export default async function Home() {
    const client = createClient();
    const {data: legalUnits, count, error} = await client
        .from('legal_unit')
        .select('tax_reg_ident, name', {count: 'exact'})
        .gt('id', 0)
        .limit(10);

    if (error) {
        console.error('⚠️failed to fetch legal units', error);
    }

    return (
        <main className="flex flex-col p-8 md:p-24 space-y-6 max-w-7xl mx-auto">
            <h1 className="font-medium text-lg">Welcome to Statbus!</h1>
            <Search legalUnits={legalUnits} count={count}/>
        </main>
    )
}
