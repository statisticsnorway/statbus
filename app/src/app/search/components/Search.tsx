"use client";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {useEffect, useState} from "react";
import TableToolbar from "@/app/search/components/TableToolbar";
import {ColumnDef, getCoreRowModel} from "@tanstack/table-core";
import {useReactTable} from "@tanstack/react-table";

type LegalUnit = {
  tax_reg_ident: string | null,
  name: string | null
}

interface SearchProps {
  readonly legalUnits: LegalUnit[],
  readonly count: number
}

export default function Search({legalUnits = [], count = 0}: SearchProps) {
  const [searchResult, setSearchResult] = useState({legalUnits, count})
  const [search, setSearch] = useState('')
  const columns: ColumnDef<LegalUnit>[] = []
  const table = useReactTable({
    columns,
    data: searchResult.legalUnits,
    getCoreRowModel: getCoreRowModel<LegalUnit>()
  })

  useEffect(() => {
    if (search === '') return setSearchResult(() => ({legalUnits, count}))
    fetch(`/search/api?q=${search}`)
      .then(response => response.json())
      .then((data) => setSearchResult(() => data))
  }, [search])

  return (
    <section className="space-y-3">
      <TableToolbar onSearch={q => setSearch(q)}/>

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
