"use client";
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useSearchContext } from "@/app/search/use-search-context";

export default function SearchResultTable() {
  const { searchResult } = useSearchContext();

  return (
    <Table>
      <StatisticalUnitTableHeader />
      <TableBody>
        {!searchResult?.statisticalUnits?.length && (
          <TableRow>
            <TableCell colSpan={5} className="py-8 text-center">
              No results found
            </TableCell>
          </TableRow>
        )}
        {searchResult?.statisticalUnits?.map((unit) => {
          return (
            <StatisticalUnitTableRow
              key={`${unit.unit_id}-${unit.unit_type}`}
              unit={unit}
            />
          );
        })}
      </TableBody>
    </Table>
  );
}
