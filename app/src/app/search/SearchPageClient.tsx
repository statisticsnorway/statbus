"use client";

import { SearchResults } from "@/app/search/SearchResults";
import TableToolbar from "@/app/search/components/table-toolbar";
import SearchResultTable from "@/app/search/components/search-result-table";
import { SearchResultCount } from "@/app/search/components/search-result-count";
import SearchResultPagination from "@/app/search/components/search-result-pagination";
import { ExportCSVLink } from "@/app/search/components/search-export-csv-link";
import { Selection } from "@/app/search/components/selection";
import type { Tables } from "@/lib/database.types";
import { useBaseData } from "@/atoms/base-data";
import { Skeleton } from "@/components/ui/skeleton";
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

interface SearchPageClientProps {
  readonly allRegions: Tables<"region_used">[];
  readonly allActivityCategories: Tables<"activity_category_used">[];
  readonly allStatuses: Tables<"status">[];
  readonly allUnitSizes: Tables<"unit_size">[];
  readonly allDataSources: Tables<"data_source_used">[];
  readonly allExternalIdentTypes: Tables<"external_ident_type_active">[];
  readonly allLegalForms: Tables<"legal_form_used">[];
  readonly allSectors: Tables<"sector_used">[];
  readonly initialUrlSearchParamsString: string;
}

// A skeleton component for the entire search page content.
function SearchPageSkeleton() {
  return (
    <main className="overflow-x-hidden">
      <div className="mx-auto flex flex-col w-full max-w-fit py-8 md:py-12 px-2 lg:px-8">
        <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
          Search for statistical units
        </h1>
        <div className="space-y-3">
          {/* Skeleton for Toolbar */}
          <div className="flex flex-wrap items-center gap-2 mb-4 p-1 lg:p-0 w-full">
            <Skeleton className="h-9 w-[250px]" />
            <Skeleton className="h-9 w-[150px]" />
            <Skeleton className="h-9 w-[150px]" />
            <Skeleton className="h-9 w-[150px]" />
          </div>
          {/* Skeleton for Table */}
          <div className="rounded-md border min-w-[300px] overflow-auto">
            <Skeleton className="h-[400px] w-full" />
          </div>
          {/* Skeleton for Pagination/Footer */}
          <div className="flex items-center justify-center text-xs text-gray-500">
            <Skeleton className="h-6 flex-1 hidden lg:inline-block" />
            <Skeleton className="h-9 w-[200px]" />
            <div className="hidden flex-1 space-x-3 justify-end flex-wrap lg:flex">
              <Skeleton className="h-9 w-[120px]" />
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}


export default function SearchPageClient({
  allRegions,
  allActivityCategories,
  allStatuses,
  allUnitSizes,
  allDataSources,
  allExternalIdentTypes,
  allLegalForms,
  allSectors,
  initialUrlSearchParamsString,
}: SearchPageClientProps) {
  const { loading: baseDataLoading } = useBaseData();
  const [baseDataReady, setBaseDataReady] = useState(false);

  // This effect "latches" the baseDataReady state. Once the initial data load
  // is complete, this component will never show the skeleton again, even if
  // baseDataLoading flaps, which prevents the unmounting of SearchResults.
  useGuardedEffect(() => {
    if (!baseDataLoading) {
      setBaseDataReady(true);
    }
  }, [baseDataLoading], 'SearchPageClient:latchBaseDataReady');

  if (!baseDataReady) {
    return <SearchPageSkeleton />;
  }

  return (
    <SearchResults
      allRegions={allRegions ?? []}
      allActivityCategories={allActivityCategories ?? []}
      allStatuses={allStatuses ?? []}
      allUnitSizes={allUnitSizes ?? []}
      allDataSources={allDataSources ?? []}
      allExternalIdentTypes={allExternalIdentTypes ?? []}
      allLegalForms={allLegalForms ?? []}
      allSectors={allSectors ?? []}
      initialUrlSearchParamsString={initialUrlSearchParamsString}
    >
      <main className="overflow-x-hidden">
        <div className="mx-auto flex flex-col w-full max-w-fit py-8 md:py-12 px-2 lg:px-8">
          <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
            Search for statistical units
          </h1>
          <div className="flex flex-wrap items-center p-1 lg:p-0 *:mb-2 *:mx-1 w-full"></div>
          <section className="space-y-3">
            <TableToolbar />
            <div className="rounded-md border min-w-[300px] overflow-auto">
              <SearchResultTable />
            </div>
            <div className="flex items-center justify-center text-xs text-gray-500">
              <SearchResultCount className="flex-1 hidden lg:inline-block" />
              <SearchResultPagination />
              <div className="hidden flex-1 space-x-3 justify-end flex-wrap lg:flex">
                <ExportCSVLink />
              </div>
            </div>
          </section>
          <section className="mt-8">
            <Selection />
          </section>
        </div>
      </main>
    </SearchResults>
  );
}
