import { Metadata } from "next";
import { Suspense } from "react";
import SectorFilter from "@/app/search/filtersV2/sector/sector-filter";
import { SearchProvider } from "@/app/search/search-provider";
import { FilterSkeleton } from "@/app/search/filter-skeleton";
import TableToolbar from "@/app/search/components/table-toolbar";
import SearchResultTable from "@/app/search/components/search-result-table";
import { SearchResultCount } from "@/app/search/components/search-result-count";
import SearchResultPagination from "@/app/search/components/search-result-pagination";
import { ExportCSVLink } from "@/app/search/components/search-export-csv-link";
import { Cart } from "@/app/search/components/cart";
import { CartProvider } from "@/app/search/cart-provider";
import RegionFilter from "@/app/search/filtersV2/region/region-filter";
import LegalFormFilter from "@/app/search/filtersV2/legal-form/legal-form-filter";
import ActivityCategoryFilter from "@/app/search/filtersV2/activity-category/activity-category-filter";
import StatisticalVariablesFilter from "@/app/search/filtersV2/statistical-variables/statistical-variables-filter";
import FullTextSearchFilter from "@/app/search/filtersV2/full-text-search-filter";
import TaxRegIdentFilter from "@/app/search/filtersV2/tax-reg-ident-filter";
import UnitTypeFilter from "@/app/search/filtersV2/unit-type-filter";
import InvalidCodesFilter from "@/app/search/filtersV2/invalid-codes-filter";
import {
  INVALID_CODES,
  SEARCH,
  TAX_REG_IDENT,
  UNIT_TYPE,
} from "@/app/search/filtersV2/url-search-params";

export const metadata: Metadata = {
  title: "StatBus | Search statistical units",
};

export default async function SearchPage({
  searchParams,
}: {
  readonly searchParams: URLSearchParams;
}) {
  const params = new URLSearchParams(searchParams);

  const [orderBy, ...orderDirections] = params.get("order")?.split(".") ?? [
    "name",
    "asc",
  ];

  const defaultCurrentPage = 1;
  const defaultPageSize = 10;
  const currentPage = Number(params.get("page")) || defaultCurrentPage;

  return (
    <SearchProvider
      order={{ name: orderBy, direction: orderDirections.join(".") }}
      pagination={{ pageNumber: currentPage, pageSize: defaultPageSize }}
    >
      <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-24">
        <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
          Search for statistical units
        </h1>
        <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
          <FullTextSearchFilter value={params.get(SEARCH)} />
          <TaxRegIdentFilter value={params.get(TAX_REG_IDENT)} />
          <UnitTypeFilter param={params.get(UNIT_TYPE)} />
          <Suspense fallback={<FilterSkeleton title="Sector" />}>
            <SectorFilter />
          </Suspense>
          <Suspense fallback={<FilterSkeleton title="Region" />}>
            <RegionFilter />
          </Suspense>
          <Suspense fallback={<FilterSkeleton title="Legal Form" />}>
            <LegalFormFilter />
          </Suspense>
          <Suspense fallback={<FilterSkeleton title="Activity Category" />}>
            <ActivityCategoryFilter />
          </Suspense>
          <Suspense fallback={<FilterSkeleton title="Statistical Variables" />}>
            <StatisticalVariablesFilter />
          </Suspense>
          <InvalidCodesFilter value={params.get(INVALID_CODES)} />
        </div>
        <CartProvider>
          <section className="space-y-3">
            <TableToolbar />
            <div className="rounded-md border overflow-hidden">
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
            <Cart />
          </section>
        </CartProvider>
      </main>
    </SearchProvider>
  );
}
