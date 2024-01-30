import Link from "next/link";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {SearchResult} from "@/app/search/search.types";

interface TableProps {
    searchResult: SearchResult
}

export default function SearchResultTable({searchResult: {statisticalUnits}}: TableProps) {
    return (
        <Table>
            <TableHeader className="bg-gray-100">
                <TableRow>
                    <TableHead className="w-[100px]">Tax ID</TableHead>
                    <TableHead>Name</TableHead>
                    <TableHead className="text-right">Activity Category Code</TableHead>
                </TableRow>
            </TableHeader>
            <TableBody>
                {
                  statisticalUnits?.map(({legal_unit_id, name, primary_activity_category_id}) => (
                    <TableRow key={legal_unit_id}>
                      <TableCell className="font-medium p-3 px-4">
                        <Link href={`/legal-units/${legal_unit_id}`}>
                          {legal_unit_id}
                        </Link>
                      </TableCell>
                      <TableCell className="p-3">{name}</TableCell>
                      <TableCell className="text-right p-3 px-4">{primary_activity_category_id}</TableCell>
                    </TableRow>
                  ))
                }
            </TableBody>
        </Table>
    )
}
