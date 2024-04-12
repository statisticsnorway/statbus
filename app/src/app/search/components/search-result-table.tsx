"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useSearchContext } from "@/app/search/use-search-context";
import { cn } from "@/lib/utils";
import { SearchResultTableBodySkeleton } from "@/app/search/components/search-result-table-body-skeleton";

export default function SearchResultTable() {
  const { searchResult, isLoading } = useSearchContext();

  return (
    <div className="relative">
      <Table className={cn("bg-white", isLoading && "")}>
        <StatisticalUnitTableHeader />
        {isLoading ? (
          <SearchResultTableBodySkeleton />
        ) : (
          <TableBody>
            {searchResult?.statisticalUnits?.map((unit) => {
              return (
                <StatisticalUnitTableRow
                  key={`${unit.unit_id}-${unit.unit_type}`}
                  unit={unit}
                />
              );
            })}
          </TableBody>
        )}
      </Table>
    </div>
  );
}
