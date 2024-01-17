"use client";
import {useEffect, useReducer, useState} from "react";
import TableToolbar from "@/app/search/components/TableToolbar";
import {Tables} from "@/lib/database.types";
import {searchFilterReducer} from "@/app/search/reducer";
import SearchResultTable from "@/app/search/components/SearchResultTable";

interface SearchProps {
  readonly legalUnits: LegalUnit[],
  readonly regions: Tables<"region">[]
  readonly activityCategories: Tables<"activity_category_available">[]
  readonly count: number
}

export default function Search({legalUnits = [], regions = [], activityCategories, count = 0}: SearchProps) {
  const [searchResult, setSearchResult] = useState({legalUnits, count})
  const [searchPrompt, setSearchPrompt] = useState('')
  const [searchFilter, searchFilterDispatch] = useReducer(searchFilterReducer, {
    selectedRegions: [],
    selectedActivityCategories: [],
    activityCategoryOptions: activityCategories.map(({label, name}) => ({label: `${label} ${name}`, value: label ?? ""})),
    regionOptions: regions.map(({code, name}) => ({label: `${code} ${name}`, value: code ?? ""}))
  })

  useEffect(() => {
    if (!searchPrompt && !searchFilter.selectedActivityCategories.length && !searchFilter.selectedRegions.length) {
      return setSearchResult(() => ({legalUnits, count}))
    }

    const searchParams = new URLSearchParams()

    if (searchPrompt) {
      searchParams.set('q', searchPrompt)
    }

    if (searchFilter.selectedRegions.length) {
      searchParams.set('region_codes', searchFilter.selectedRegions.join(','))
    }

    if (searchFilter.selectedActivityCategories.length) {
      searchParams.set('activity_category_codes', searchFilter.selectedActivityCategories.join(','))
    }

    fetch(`/search/api?${searchParams}`)
      .then(response => response.json())
      .then((data) => setSearchResult(() => data))
  }, [searchPrompt, searchFilter.selectedActivityCategories, searchFilter.selectedRegions, legalUnits, count])

  return (
    <section className="space-y-3">
      <TableToolbar filter={searchFilter} dispatch={searchFilterDispatch} onSearch={q => setSearchPrompt(q)}/>
      <div className="rounded-md border">
        <SearchResultTable searchResult={searchResult} />
      </div>
      <div className="px-4">
        <small className="text-xs text-gray-500">
          Showing {searchResult?.legalUnits?.length} of total {searchResult?.count}
        </small>
      </div>
    </section>
  )
}
