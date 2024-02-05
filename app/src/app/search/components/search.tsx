"use client";
import TableToolbar from "@/app/search/components/table-toolbar";
import {Tables} from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/search-result-table";
import useSearch from "@/app/search/hooks/use-search";
import {useFilter} from "@/app/search/hooks/use-filter";
import type {SearchResult} from "@/app/search/search.types";

interface SearchProps {
    readonly initialSearchResult: SearchResult
    readonly regions: Tables<"region">[]
    readonly activityCategories: Tables<"activity_category_available">[]
    readonly statisticalVariables: Tables<"stat_definition">[]
}

export default function Search(
    {
        initialSearchResult,
        regions = [],
        activityCategories,
        statisticalVariables
    }: SearchProps
) {
    const [filters, searchFilterDispatch] = useFilter({activityCategories, regions, statisticalVariables})
    const {data: searchResult} = useSearch(filters, initialSearchResult)

    return (
        <section className="space-y-3">
            <TableToolbar dispatch={searchFilterDispatch} filters={filters} />
            <div className="rounded-md border">
                <SearchResultTable regions={regions} activityCategories={activityCategories} searchResult={searchResult ?? initialSearchResult}/>
            </div>
            <div className="px-4">
                <small className="text-xs text-gray-500">
                    Showing {searchResult?.statisticalUnits?.length} of total {searchResult?.count}
                </small>
            </div>
        </section>
    )
}

