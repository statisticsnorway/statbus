"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useSearchContext } from "@/app/search/use-search-context";
import { cn } from "@/lib/utils";
import { SearchResultTableBodySkeleton } from "@/app/search/components/search-result-table-body-skeleton";
import { useRegionLevel } from "@/app/search/hooks/useRegionLevel";
import { useTableColumns } from "../use-table-columns";

export default function SearchResultTable() {
  const { searchResult, error, isLoading, allRegions: regions } = useSearchContext();
  const { regionLevel, setRegionLevel } = useRegionLevel();
  const { bodyRowSuffix } = useTableColumns();
  const maxRegionLevel = Math.max(
    ...(regions?.map((region) => region.level ?? 0) ?? [])
  );

  if (error) {
    return (
      <div className="flex items-center justify-center p-4 border border-red-400 bg-red-100 text-red-700 rounded-lg shadow-md">
        <svg
          className="w-6 h-6 mr-2 text-red-700"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M18.364 5.636a9 9 0 11-12.728 0 9 9 0 0112.728 0zM12 9v2m0 4h.01"
          ></path>
        </svg>
        <span>Error loading data: {error.message}</span>
      </div>
    );
  }

  return (
    <div className="relative">
      <Table className={cn("bg-white", isLoading && "")}>
        {!isLoading && (
          <StatisticalUnitTableHeader
            regionLevel={regionLevel}
            setRegionLevel={setRegionLevel}
            maxRegionLevel={maxRegionLevel}
          />
        )}
        {isLoading ? (
          <SearchResultTableBodySkeleton />
        ) : (
          <TableBody>
            {searchResult?.statisticalUnits?.map((unit) => (
              <StatisticalUnitTableRow
                key={`sutr-${bodyRowSuffix(unit)}`}
                unit={unit}
                regionLevel={regionLevel}
              />
            ))}
          </TableBody>
        )}
      </Table>
    </div>
  );
}
