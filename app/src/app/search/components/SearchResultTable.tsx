import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";

interface TableProps {
  searchResult: {
    legalUnits: LegalUnit[],
    count: number
  }
}

export default function SearchResultTable({searchResult: {legalUnits}}: TableProps) {
  return (
    <Table>
      <TableHeader className="bg-gray-50">
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
          (legalUnits)?.map((legalUnit) => (
            <TableRow key={legalUnit.tax_reg_ident}>
              <TableCell className="font-medium p-3 px-4">{legalUnit.tax_reg_ident}</TableCell>
              <TableCell className="p-3">{legalUnit.name}</TableCell>
              <TableCell className="p-3">N/A</TableCell>
              <TableCell className="text-right p-3">N/A</TableCell>
              <TableCell className="text-right p-3 px-4">N/A</TableCell>
            </TableRow>
          ))
        }
      </TableBody>
    </Table>
  )
}
