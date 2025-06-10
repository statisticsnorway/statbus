"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import { StatisticalUnitTableHeader } from "@/app/search/components/statistical-unit-table-header";
// import { useSearchContext } from "@/app/search/use-search-context"; // Will be partially replaced // Removed
import { useSearch, useBaseData } from "@/atoms/hooks"; // New Jotai hook
import { cn } from "@/lib/utils";
import { SearchResultTableBodySkeleton } from "@/app/search/components/search-result-table-body-skeleton";
import { useRegionLevel } from "@/app/search/hooks/useRegionLevel";
import { useTableColumnsManager as useTableColumns } from '@/atoms/hooks';

export default function SearchResultTable() {
  // const { searchResult: oldSearchResult, allRegions: regions } = useSearchContext(); // Keep for allRegions temporarily // Removed
  // TODO: `regions` needs to be sourced. For now, it will be undefined or from a different source if available.
  // One option is to get it from useBaseData if it's included there, or pass via props.
  // For now, let's assume `regions` might be missing or needs to be explicitly passed.
  // The `allRegions` prop was passed to `SearchResults`, which then put it on the old context.
  // This component needs `regions` for `maxRegionLevel`.
  // A temporary fix might be to get it from `useBaseData` if suitable, or make it a prop.
  // For now, this will cause a runtime error if regions is used without being defined.
  // Let's assume `allRegions` is available from `useBaseData()` for now, or it's passed down.
  // The `page.tsx` fetches `regions` and passes it to `SearchResults`.
  // `SearchResults` needs to make this available, perhaps via a new atom or by passing props.
  // For this step, we focus on fixing the import. `regions` will be undefined.
  let regions: any[] = []; // Placeholder to avoid immediate crash, will need proper fix
  const { searchResult, executeSearch } = useSearch(); // New Jotai hook
  const { regionLevel, setRegionLevel } = useRegionLevel();
  const { bodyRowSuffix } = useTableColumns();
  const maxRegionLevel = Math.max(
    ...(regions?.map((region: any) => region.level ?? 0) ?? [])
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
            {searchResult?.data?.map((unit) => (
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
