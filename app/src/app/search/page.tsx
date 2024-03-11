import {createClient} from "@/lib/supabase/server";
import Search from "@/app/search/components/search";
import {Metadata} from "next";
import {createFilters} from "@/app/search/create-filters";

export const metadata: Metadata = {
    title: "StatBus | Search statistical units"
}

export default async function SearchPage({ searchParams }: { readonly searchParams: URLSearchParams }) {
    const client = createClient();

    const sectorPromise = client
      .from('sector_used')
      .select()
      .not('code', 'is', null)

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
        {data: sectors, error: sectorsError},
        {data: regions, error: regionsError},
        {data: activityCategories, error: activityCategoriesError},
        {data: statisticalVariables}
    ] = await Promise.all([
        sectorPromise,
        regionPromise,
        activityCategoryPromise,
        statDefinitionPromise
    ]);

    if (sectorsError) {
        console.error('⚠️failed to fetch sectors', sectorsError);
    }

    if (regionsError) {
        console.error('⚠️failed to fetch regions', regionsError);
    }

    if (activityCategoriesError) {
        console.error('⚠️failed to fetch activity categories', activityCategoriesError);
    }

    const urlSearchParams = new URLSearchParams(searchParams);

    const searchFilters = createFilters({
        activityCategories: activityCategories ?? [],
        regions: regions ?? [],
        statisticalVariables: statisticalVariables ?? [],
        sectors: sectors ?? []
    }, urlSearchParams);

    const [orderBy, ...orderDirections] = urlSearchParams.get('order')?.split('.') ?? ['name', 'asc'];

    const defaultCurrentPage = 1
    const defaultPageSize = 10

    const currentPage = Number(urlSearchParams.get('page')) || defaultCurrentPage
    

    return (
        <main className="flex flex-col py-8 px-2 md:py-24 mx-auto w-full max-w-5xl">
            <h1 className="font-medium text-xl text-center mb-12">Search for statistical units</h1>
            <Search
                regions={regions ?? []}
                activityCategories={activityCategories ?? []}
                statisticalVariables={statisticalVariables ?? []}
                searchFilters={searchFilters}
                searchOrder={{name: orderBy, direction: orderDirections.join('.')}}
                searchPagination={{pageNumber: currentPage, pageSize: defaultPageSize}}
            />
        </main>
    )
}
