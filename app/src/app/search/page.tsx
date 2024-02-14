import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/components/search";
import {Metadata} from "next";

export const metadata: Metadata = {
    title: "StatBus | Search statistical units"
}

export default async function SearchPage() {
    const client = createClient();
    const statisticalUnitPromise = client
        .from('statistical_unit')
        .select('name, tax_reg_ident, primary_activity_category_path, unit_id, unit_type, physical_region_path', {count: 'exact'})
        .in('unit_type', ['enterprise'])
        .order('tax_reg_ident', {ascending: false})
        .limit(10);

    const regionPromise = client
        .from('region_used')
        .select()

    const activityCategoryPromise = client
        .from('activity_category_used')
        .select();

    const statDefinitionPromise = client
        .from('stat_definition')
        .select()
        .order('priority', {ascending: true});

    const [
        {data: statisticalUnits, count, error: statisticalUnitsError},
        {data: regions, error: regionsError},
        {data: activityCategories, error: activityCategoriesError},
        {data: statisticalVariables}
    ] = await Promise.all([
        statisticalUnitPromise,
        regionPromise,
        activityCategoryPromise,
        statDefinitionPromise
    ]);

    if (statisticalUnitsError) {
        console.error('⚠️failed to fetch statistical units', statisticalUnitsError);
    }

    if (regionsError) {
        console.error('⚠️failed to fetch regions', regionsError);
    }

    if (activityCategoriesError) {
        console.error('⚠️failed to fetch activity categories', activityCategoriesError);
    }

    return (
        <main className="flex flex-col py-8 px-2 md:py-24 mx-auto w-full max-w-5xl">
            <h1 className="font-medium text-xl text-center mb-12">Search for statistical units</h1>
            <Search
                regions={regions ?? []}
                activityCategories={activityCategories ?? []}
                statisticalVariables={statisticalVariables ?? []}
                initialSearchResult={{statisticalUnits: statisticalUnits ?? [], count: count ?? 0}}
            />
        </main>
    )
}
