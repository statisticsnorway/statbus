import Link from "next/link";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {SearchResult} from "@/app/search/search.types";
import {Tables} from "@/lib/database.types";

interface TableProps {
  readonly searchResult: SearchResult
  readonly regions: Tables<'region'>[]
}

export default function SearchResultTable({searchResult: {statisticalUnits}, regions}: TableProps) {
  const getRegionByPath = (physical_region_path: unknown) =>
    regions.find(({path}) => path === physical_region_path);

  return (
    <Table>
      <TableHeader className="bg-gray-100">
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead className="text-right">Region</TableHead>
          <TableHead className="text-right">Activity Category Code</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {
          statisticalUnits?.map(({legal_unit_id, tax_reg_ident, name, physical_region_path, primary_activity_category_path}) => (
              <TableRow key={legal_unit_id}>
                  <TableCell className="p-2 flex flex-col">
                      <div>
                          <Link href={`/legal-units/${legal_unit_id}`} className="font-medium">
                              {name}
                          </Link>
                      </div>
                      <small className="text-gray-700">{tax_reg_ident}</small>
                  </TableCell>
                  <TableCell className="p-2 text-right">{getRegionByPath(physical_region_path)?.name}</TableCell>
                  <TableCell className="text-right p-2 px-4">{primary_activity_category_path as string}</TableCell>
              </TableRow>
          ))
        }
      </TableBody>
    </Table>
  )
}
