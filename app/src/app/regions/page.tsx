"use client";
import { RegionsHeader } from "./regions-header";
import { TableResultCount } from "@/components/table/table-result-count";
import TablePagination from "../../components/table/table-pagination";
import RegionTable from "./region-table";
import useRegion from "./use-region";
import TableFilters from "./region-table-filters";

export default function RegionPage() {
  const { data, pagination, setPagination, queries, setQueries, refresh } = useRegion();

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <RegionsHeader view="list" />
      <section className="space-y-3">
        <TableFilters
          setQueries={setQueries}
          setPagination={setPagination}
          queries={queries}
        />
        <div className="rounded-md border overflow-hidden">
          <RegionTable regions={data?.regions ?? []} onChanged={refresh} />
        </div>
        <div className="lg:grid lg:grid-cols-3 items-center justify-center text-xs text-gray-500">
          <TableResultCount
            pagination={pagination}
            total={data?.count ?? 0}
            className="hidden lg:inline-block"
          />
          <TablePagination
            pagination={pagination}
            setPagination={setPagination}
            total={data?.count ?? 0}
          />
        </div>
      </section>
    </main>
  );
}
