"use client";
import {Input} from "@/components/ui/input";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {Tables} from "@/lib/database.types";
import {Label} from "@/components/ui/label";
import {useEffect, useState} from "react";

interface SearchProps {
  readonly legalUnits: Tables<'legal_unit'>[] | null,
  readonly count: number | null
}

export default function Search({legalUnits = [], count = 0}: SearchProps) {
  const [searchResult, setSearchResult] = useState({legalUnits, count})
  const [search, setSearch] = useState('')

  useEffect(() => {
    fetch(`/search/api?q=${search}`)
      .then(response => response.json())
      .then((data) => setSearchResult(() => data))
  }, [search])

  return (
    <section className="space-y-3">
      <div className="w-full items-center bg-green-100 p-6 space-y-3">
        <div className="flex justify-between">
          <Label htmlFor="search-prompt">Find units by name or ID</Label>
          <small className="text-xs text-gray-500">Showing {searchResult?.legalUnits?.length} of total {searchResult?.count}</small>
        </div>
        <Input
          type="text"
          id="search-prompt"
          placeholder="Legal Unit"
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

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
            searchResult?.legalUnits?.map((legalUnit) => (
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
    </section>
  )
}
