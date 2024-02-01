import Link from "next/link";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {SearchResult} from "@/app/search/search.types";

interface TableProps {
  readonly searchResult: SearchResult
}

export default function SearchResultTable({searchResult: {statisticalUnits}}: TableProps) {
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
          statisticalUnits?.map(({legal_unit_id, name, physical_region_id, primary_activity_category_id}) => (
            <TableRow key={legal_unit_id}>
              <TableCell className="p-3">
                <Link href={`/legal-units/${legal_unit_id}`} className="font-medium">
                  {name}
                </Link>
              </TableCell>
              <TableCell className="p-3 text-right">{physical_region_id}</TableCell>
              <TableCell className="text-right p-3 px-4">{primary_activity_category_id}</TableCell>
            </TableRow>
          ))
        }
      </TableBody>
    </Table>
  )
}
