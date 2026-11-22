"use client";
import Link from "next/link";
import { Map as MapIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { TableResultCount } from "@/components/table/table-result-count";
import TablePagination from "../../components/table/table-pagination";
import RegionTable from "./region-table";
import useRegion from "./use-region";
import TableFilters from "./region-table-filters";
export default function RegionPage() {
  const { data, pagination, setPagination, queries, setQueries } = useRegion();

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <h1 className="text-center mb-6 text-xl lg:mb-12 lg:text-2xl">
        Region Hierarchy
      </h1>
      <section className="space-y-3">
        <div className="flex items-start justify-between gap-3">
          <TableFilters
            setQueries={setQueries}
            setPagination={setPagination}
            queries={queries}
          />
          <Link href="/regions/map" className={buttonVariants({ variant: "outline", size: "sm" })} data-regions-map-link="">
            <MapIcon className="mr-1.5 h-4 w-4" />
            Map
          </Link>
        </div>
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
