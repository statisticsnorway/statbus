import RegionTable from "./region-table";
import RegionPagination from "./region-pagination";
import { RegionProvider } from "./region-provider";
import { RegionResultCount } from "./region-result-count";
import RegionSearchFilter from "./region-search-filter";
import { ResetFilterButton } from "./reset-filter-button";

export default async function RegionsPage({
  searchParams,
}: {
  readonly searchParams: URLSearchParams;
}) {
  const params = new URLSearchParams(searchParams);

  const [orderBy, ...orderDirections] = params.get("order")?.split(".") ?? [
    "id",
    "asc",
  ];

  const defaultCurrentPage = 1;
  const defaultPageSize = 10;
  const currentPage = Number(params.get("page")) || defaultCurrentPage;
  const nameSearch = params.get("name");
  const codeSearch = params.get("code");

  return (
    <RegionProvider
      order={{ name: orderBy, direction: orderDirections.join(".") }}
      pagination={{ pageNumber: currentPage, pageSize: defaultPageSize }}
    >
      <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-24">
        <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
          Regions
        </h1>
        <section className="space-y-3">
          <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
            <RegionSearchFilter urlSearchParam={nameSearch} name="name" />
            <RegionSearchFilter urlSearchParam={codeSearch} name="code" />
            <ResetFilterButton />
          </div>
          <div className="rounded-md border overflow-hidden">
            <RegionTable />
          </div>
          <div className="flex items-center justify-center text-xs text-gray-500">
            <RegionResultCount className="flex-1 hidden lg:inline-block" />
            <RegionPagination />
            <div className="hidden flex-1 space-x-3 justify-end flex-wrap lg:flex"></div>
          </div>
        </section>
      </main>
    </RegionProvider>
  );
}
