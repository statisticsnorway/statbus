"use client";
import {useState} from "react";
import TableToolbar from "@/app/search/components/TableToolbar";
import {Tables} from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/SearchResultTable";
import useSearch from "@/app/search/hooks/useSearch";
import {useFilter} from "@/app/search/hooks/useFilter";

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
  const [searchPrompt, setSearchPrompt] = useState('')
  const [filters, searchFilterDispatch] = useFilter({activityCategories, regions, statisticalVariables})
  const {data: searchResult} = useSearch(searchPrompt, filters, initialSearchResult)

  return (
    <section className="space-y-3">
      <TableToolbar dispatch={searchFilterDispatch} filters={filters} onSearch={q => setSearchPrompt(q)}/>
      <div className="rounded-md border">
        <SearchResultTable searchResult={searchResult ?? initialSearchResult}/>
      </div>
      <div className="px-4">
        <small className="text-xs text-gray-500">
          Showing {searchResult?.legalUnits?.length} of total {searchResult?.count}
        </small>
      </div>
    </section>
  )
}
