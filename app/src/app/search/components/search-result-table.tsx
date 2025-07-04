"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
import { useBaseData } from "@/atoms/base-data";
import { useSearch, StatisticalUnit } from "@/atoms/search";
import { cn } from "@/lib/utils";
import { SearchResultTableBodySkeleton } from "@/app/search/components/search-result-table-body-skeleton";
import { useRegionLevel } from "@/app/search/hooks/useRegionLevel";
import type { Tables } from "@/lib/database.types";
import { useTableColumnsManager as useTableColumns } from '@/atoms/search';

export default function SearchResultTable() {
  const { searchResult, executeSearch, allRegions } = useSearch();
  const { regionLevel, setRegionLevel } = useRegionLevel();
  const { bodyRowSuffix } = useTableColumns();
  const maxRegionLevel = Math.max(
    ...(allRegions?.map((region: Tables<"region_used">) => region.level ?? 0) ?? [])
  );

  if (searchResult.error) {
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
        <span>Error loading data: {searchResult.error}</span>
      </div>
    );
  }

  return (
    <div className="relative">
      <Table className={cn("bg-white", searchResult.loading && "")}>
        {!searchResult.loading && (
          <StatisticalUnitTableHeader
            regionLevel={regionLevel}
            setRegionLevel={setRegionLevel}
            maxRegionLevel={maxRegionLevel}
          />
        )}
        {searchResult.loading ? (
          <SearchResultTableBodySkeleton />
        ) : (
          <TableBody>
            {searchResult?.data?.map((unit: StatisticalUnit) => (
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
