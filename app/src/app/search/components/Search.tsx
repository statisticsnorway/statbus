"use client";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {useEffect, useReducer, useState} from "react";
import TableToolbar from "@/app/search/components/TableToolbar";
import {Tables} from "@/lib/database.types";
import {searchFilterReducer} from "@/app/search/reducer";

type LegalUnit = {
  tax_reg_ident: string | null,
  name: string | null
}

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
    regionOptions: regions.map(({id, name}) => ({label: `${id} ${name}`, value: id.toString(10)}))
  })

  useEffect(() => {
    if (searchPrompt === '') return setSearchResult(() => ({legalUnits, count}))
    fetch(`/search/api?q=${searchPrompt}`)
      .then(response => response.json())
      .then((data) => setSearchResult(() => data))
  }, [searchPrompt, count, legalUnits])

  return (
    <section className="space-y-3">
      <TableToolbar filter={searchFilter} dispatch={searchFilterDispatch} onSearch={q => setSearchPrompt(q)}/>

      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[100px]">ID</TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Employees</TableHead>
              <TableHead className="text-right">Region</TableHead>
              <TableHead className="text-right">Activity Category Code</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {
              (searchResult?.legalUnits)?.map((legalUnit) => (
                <TableRow key={legalUnit.tax_reg_ident}>
                  <TableCell className="font-medium">{legalUnit.tax_reg_ident}</TableCell>
                  <TableCell>{legalUnit.name}</TableCell>
                  <TableCell>N/A</TableCell>
                  <TableCell className="text-right">N/A</TableCell>
                  <TableCell className="text-right">N/A</TableCell>
                </TableRow>
              ))
            }
          </TableBody>
        </Table>
      </div>
      <div className="px-4">
        <small className="text-xs text-gray-500">
          Showing {searchResult?.legalUnits?.length} of total {searchResult?.count}
        </small>
      </div>
    </section>
  )
}
