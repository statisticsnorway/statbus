import { Metadata } from "next";
import SearchResults from "@/app/search/SearchResults";
import TableToolbar from "@/app/search/components/table-toolbar";
import SearchResultTable from "@/app/search/components/search-result-table";
import { SearchResultCount } from "@/app/search/components/search-result-count";
import SearchResultPagination from "@/app/search/components/search-result-pagination";
import { ExportCSVLink } from "@/app/search/components/search-export-csv-link";
import { Cart } from "@/app/search/components/cart";
import { CartProvider } from "@/app/search/cart-provider";
import { createClient } from "@/utils/supabase/server";

export const metadata: Metadata = {
  title: "Statbus | Search statistical units",
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

  /* TODO - Remove this once the search results include the activity category and region names
   * Until activity category and region names are included in the search results,
   * we need to provide activity categories and regions via the search provider
   * so that the names can be resolved and displayed in the search results.
   *
   * A better solution would be to include the names in the search results
   * so that we do not need any blocking calls to supabase here.
   */
  const {client} = createClient();
  const [activityCategories, regions] = await Promise.all([
    client.from("activity_category_used").select(),
    client.from("region_used").select(),
  ]);

  const defaultCurrentPage = 1;
  const defaultPageSize = 10;
  const currentPage = Number(params.get("page")) || defaultCurrentPage;

  return (
    <SearchResults
      order={{ name: orderBy, direction: orderDirections.join(".") }}
      pagination={{ pageNumber: currentPage, pageSize: defaultPageSize }}
      regions={regions.data}
      activityCategories={activityCategories.data}
      urlSearchParams={params}
    >
      <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
        <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
          Search for statistical units
        </h1>
        <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full"></div>
        <CartProvider>
          <section className="space-y-3">
            <TableToolbar urlSearchParams={params} />
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
    </SearchResults>
  );
}
