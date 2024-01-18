"use client";
import {useState} from "react";
import TableToolbar from "@/app/search/components/TableToolbar";
import {Tables} from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/SearchResultTable";
import useSearch from "@/app/search/hooks/useSearch";
import {useFilter} from "@/app/search/hooks/useFilter";

interface SearchProps {
  readonly legalUnits: LegalUnit[],
  readonly regions: Tables<"region">[]
  readonly activityCategories: Tables<"activity_category_available">[]
  readonly count: number
}

export default function Search({legalUnits = [], regions = [], activityCategories, count = 0}: SearchProps) {
  const [searchPrompt, setSearchPrompt] = useState('')
  const [filters, searchFilterDispatch] = useFilter({activityCategories, regions})
  const {data} = useSearch(searchPrompt, filters, {legalUnits, count})

  return (
    <section className="space-y-3">
      <TableToolbar dispatch={searchFilterDispatch} filters={filters} onSearch={q => setSearchPrompt(q)}/>
      <div className="rounded-md border">
        <SearchResultTable searchResult={data ?? {legalUnits, count}}/>
      </div>
      <div className="px-4">
        <small className="text-xs text-gray-500">
          Showing {data?.legalUnits?.length} of total {data?.count}
        </small>
      </div>
    </section>
  )
}

