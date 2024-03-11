"use client";
import TableToolbar from "@/app/search/components/table-toolbar";
import {Tables} from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/search-result-table";
import {ExportCSVLink} from "@/app/search/components/search-export-csv-link";
import {SearchProvider} from "@/app/search/search-provider";
import {SearchResultCount} from "@/app/search/components/search-result-count";
import SearchResultPagination from "./search-result-pagination";

interface SearchProps {
  readonly regions: Tables<"region_used">[]
  readonly activityCategories: Tables<"activity_category_available">[]
  readonly statisticalVariables: Tables<"stat_definition">[]
  readonly searchFilters: SearchFilter[]
  readonly searchOrder: SearchOrder
  readonly searchPage: SearchPage
}

export default function Search({regions = [], activityCategories, searchFilters, searchOrder, searchPage}: SearchProps) {
  return (
    <SearchProvider
      filters={searchFilters}
      order={searchOrder}
      page={searchPage}
      regions={regions}
      activityCategories={activityCategories}
    >
      <section className="space-y-3">
        <TableToolbar/>
        <div className="rounded-md border">
          <SearchResultTable/>
        </div>
        <div className="flex justify-between text-xs text-gray-500 items-center">
          <SearchResultCount/>
          <SearchResultPagination/>
          <div className="space-x-3 hidden lg:flex">
            <ExportCSVLink/>
          </div>
        </div>
      </section>
    </SearchProvider>
  )
}

