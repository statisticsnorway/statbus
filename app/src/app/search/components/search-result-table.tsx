"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useSearchContext } from "@/app/search/use-search-context";
import { cn } from "@/lib/utils";
import { SearchResultTableBodySkeleton } from "@/app/search/components/search-result-table-body-skeleton";
import { useState } from "react";
export default function SearchResultTable() {
  const { searchResult, isLoading, regions } = useSearchContext();
  const [regionLevel, setRegionLevel] = useState<number>(1);
  const maxRegionLevel = Math.max(
    ...(regions?.map((region) => region.level ?? 0) ?? [])
  );
  return (
    <div className="relative">
      <Table className={cn("bg-white", isLoading && "")}>
        <StatisticalUnitTableHeader
          regionLevel={regionLevel}
          setRegionLevel={setRegionLevel}
          maxRegionLevel={maxRegionLevel}
        />
        {isLoading ? (
          <SearchResultTableBodySkeleton />
        ) : (
          <TableBody>
            {searchResult?.statisticalUnits?.map((unit) => {
              return (
                <StatisticalUnitTableRow
                  key={`${unit.unit_type}-${unit.unit_id}-${unit.valid_from}`}
                  unit={unit}
                  regionLevel={regionLevel}
                />
              );
            })}
          </TableBody>
        )}
      </Table>
    </div>
  );
}
