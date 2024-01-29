import Link from "next/link";
import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {SearchResult} from "@/app/search/search.types";

interface TableProps {
    searchResult: SearchResult
}

export default function SearchResultTable({searchResult: {legalUnits}}: TableProps) {
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
                  legalUnits?.map((legalUnit) => (
                    <TableRow key={legalUnit.tax_reg_ident}>
                      <TableCell className="font-medium p-3 px-4">
                        <Link href={`/legal-units/${legalUnit.tax_reg_ident}`}>
                          {legalUnit.tax_reg_ident}
                        </Link>
                      </TableCell>
                      <TableCell className="p-3">{legalUnit.name}</TableCell>
                      <TableCell className="text-right p-3 px-4">{legalUnit.primary_activity_category_code}</TableCell>
                    </TableRow>
                  ))
                }
            </TableBody>
        </Table>
    )
}
