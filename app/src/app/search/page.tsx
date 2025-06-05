export const dynamic = 'force-dynamic';

import { Metadata } from "next";
import { SearchResults } from "@/app/search/SearchResults";
import TableToolbar from "@/app/search/components/table-toolbar";
import SearchResultTable from "@/app/search/components/search-result-table";
import { SearchResultCount } from "@/app/search/components/search-result-count";
import SearchResultPagination from "@/app/search/components/search-result-pagination";
import { ExportCSVLink } from "@/app/search/components/search-export-csv-link";
import { Selection } from "@/app/search/components/selection";
import { SelectionProvider } from "@/app/search/selection-provider";
import { getServerRestClient } from "@/context/RestClientStore"; // Use server client
import { toURLSearchParams, URLSearchParamsDict } from "@/lib/url-search-params-dict";
import { defaultOrder } from "./search-filter-reducer";
import { SearchOrder } from "./search";

export const metadata: Metadata = {
  title: "Search statistical units",
};

export default async function SearchPage(props: { searchParams: Promise<URLSearchParamsDict> }) {
  const initialUrlSearchParamsDict = await props.searchParams;
  const initialUrlSearchParams = toURLSearchParams(initialUrlSearchParamsDict);

  /* TODO - Remove this once the search results include the activity category and region names
   * Until activity category and region names are included in the search results,
   * we need to provide activity categories and regions via the search provider
   * so that the names can be resolved and displayed in the search results.
   *
   * A better solution would be to include the names in the search results
   * so that we do not need any blocking calls to supabase here.
   */
  const client = await getServerRestClient();
  const [
    { data: activityCategories },
    { data: regions },
    { data: statuses },
    { data: unitSizes },
    { data: dataSources },
  ] = await Promise.all([
    client.from("activity_category_used").select(),
    client.from("region_used").select(),
    client.from("status").select().filter("active", "eq", true),
    client.from("unit_size").select().filter("active", "eq", true),
    client.from("data_source").select().filter("active", "eq", true),
  ]);

  let order = defaultOrder;

  const orderParam = initialUrlSearchParams.get("order")
  if (orderParam){
    const [orderBy, orderDirection] = orderParam.split(".");
    const validOrderDirection: "asc" | "desc.nullslast" =
      orderDirection === "desc.nullslast" ? "desc.nullslast" : "asc"; // Default to "asc" if invalid
    order = { name: orderBy, direction: validOrderDirection } as SearchOrder;
  }

  const defaultCurrentPage = 1;
  const defaultPageSize = 10;
  const currentPage = Number(initialUrlSearchParams.get("page")) || defaultCurrentPage;

  return (
    <SearchResults
      initialOrder={order}
      initialPagination={{ pageNumber: currentPage, pageSize: defaultPageSize }}
      allRegions={regions ?? []}
      allActivityCategories={activityCategories ?? []}
      allStatuses={statuses ?? []}
      allUnitSizes={unitSizes ?? []}
      allDataSources={dataSources ?? []}
      initialUrlSearchParamsDict={initialUrlSearchParamsDict}
    >
      <main className="overflow-x-hidden">
        <div className="mx-auto flex flex-col w-full max-w-fit py-8 md:py-12 px-2 lg:px-8">
          <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
            Search for statistical units
          </h1>
          <div className="flex flex-wrap items-center p-1 lg:p-0 *:mb-2 *:mx-1 w-full"></div>
          <SelectionProvider>
            <section className="space-y-3">
              <TableToolbar
                initialUrlSearchParamsDict={initialUrlSearchParamsDict}
              />
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
          </SelectionProvider>
        </div>
      </main>
    </SearchResults>
  );
}
