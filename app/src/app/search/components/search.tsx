"use client";
import TableToolbar from "@/app/search/components/table-toolbar";
import {Tables} from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/search-result-table";
import useSearch from "@/app/search/hooks/use-search";
import {useFilter} from "@/app/search/hooks/use-filter";
import {ExportCSVLink} from "@/app/search/components/search-export-csv-link";
import SaveSearchButton from "@/app/search/components/search-save-button";
import useUpdatedUrlSearchParams from "@/app/search/hooks/use-updated-url-search-params";
import {SearchFilter} from "@/app/search/search.types";

interface SearchProps {
    readonly regions: Tables<"region_used">[]
    readonly activityCategories: Tables<"activity_category_available">[]
    readonly statisticalVariables: Tables<"stat_definition">[]
    readonly filters: SearchFilter[][]
}

export default function Search(
    {
        regions = [],
        activityCategories,
        filters: initialFilters
    }: SearchProps
) {
    const [filters, searchFilterDispatch] = useFilter(initialFilters)
    const {search: { data: searchResult}, searchParams} = useSearch(filters)

    useUpdatedUrlSearchParams(filters)

    return (
        <section className="space-y-3">
            <TableToolbar dispatch={searchFilterDispatch} filters={filters} />
            <div className="rounded-md border">
                <SearchResultTable regions={regions} activityCategories={activityCategories} searchResult={searchResult}/>
            </div>
            <div className="flex justify-between text-xs text-gray-500 items-center">
                <span className="indent-2.5">
                    Showing {searchResult?.statisticalUnits?.length} of total {searchResult?.count} results
                </span>
                <div className="space-x-3 hidden lg:flex">
                  <SaveSearchButton disabled />
                  <ExportCSVLink searchResult={searchResult} searchParams={searchParams} />
                </div>
            </div>
        </section>
    )
}
