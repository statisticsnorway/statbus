"use client";
import TableToolbar from "@/app/search/components/table-toolbar";
import { Tables } from "@/lib/database.types";
import SearchResultTable from "@/app/search/components/search-result-table";
import { ExportCSVLink } from "@/app/search/components/search-export-csv-link";
import { SearchProvider } from "@/app/search/search-provider";
import { SearchResultCount } from "@/app/search/components/search-result-count";
import { CartProvider } from "@/app/search/cart-provider";
import { Cart } from "@/app/search/components/cart";
import SearchResultPagination from "./search-result-pagination";

interface SearchProps {
  readonly regions: Tables<"region_used">[];
  readonly activityCategories: Tables<"activity_category_available">[];
  readonly statisticalVariables: Tables<"stat_definition">[];
  readonly searchFilters: SearchFilter[];
  readonly searchOrder: SearchOrder;
  readonly searchPagination: SearchPagination;
}

export default function Search({
  regions = [],
  activityCategories,
  searchFilters,
  searchOrder,
  searchPagination,
}: SearchProps) {
  return (
    <CartProvider>
      <SearchProvider
        filters={searchFilters}
        order={searchOrder}
        pagination={searchPagination}
        regions={regions}
        activityCategories={activityCategories}
      >
        <section className="space-y-3">
          <TableToolbar />
          <div className="rounded-md border">
            <SearchResultTable />
          </div>
          <div className="flex items-center justify-between text-xs text-gray-500">
            <SearchResultCount />
            <SearchResultPagination />
            <div className="hidden space-x-3 lg:flex">
              <ExportCSVLink />
            </div>
          </div>
        </section>
        <section className="mt-8">
          <Cart />
        </section>
      </SearchProvider>
    </CartProvider>
  );
}
