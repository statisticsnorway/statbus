"use client";
import { RegionsHeader } from "./regions-header";
import { TableResultCount } from "@/components/table/table-result-count";
import TablePagination from "../../components/table/table-pagination";
import RegionTable from "./region-table";
import useRegion from "./use-region";
import TableFilters from "./region-table-filters";
import { useSearchParams } from "next/navigation";

export default function RegionPage() {
  // ?coordinates=none: only the regions without a centre point, linked from the Regions map.
  const noCoordinates = useSearchParams()?.get("coordinates") === "none";
  const { data, pagination, setPagination, queries, setQueries } = useRegion({ noCoordinates });

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
          <RegionTable regions={data?.regions ?? []} />
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
