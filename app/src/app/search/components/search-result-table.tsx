"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useSearchContext } from "@/app/search/use-search-context";
import { Loader } from "lucide-react";
import { cn } from "@/lib/utils";

export default function SearchResultTable() {
  const { searchResult, isLoading } = useSearchContext();

  return (
    <div className="relative">
      <Table className={cn("bg-white", isLoading && "blur-md")}>
        <StatisticalUnitTableHeader />
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
      </Table>
      {isLoading && (
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
          <Loader className="animate-spin duration-1000 h-8 w-8 stroke-ssb-dark" />
        </div>
      )}
      {!isLoading && !searchResult?.statisticalUnits?.length && (
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
          <span>No results found</span>
        </div>
      )}
    </div>
  );
}
