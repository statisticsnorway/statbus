"use client";
import { useState } from "react";
import { RegionsHeader } from "./regions-header";
import { TableResultCount } from "@/components/table/table-result-count";
import TablePagination from "../../components/table/table-pagination";
import RegionTable from "./region-table";
import useRegion from "./use-region";
import TableFilters from "./region-table-filters";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";

export default function RegionPage() {
  const { data, pagination, setPagination, queries, setQueries, refresh } = useRegion();
  // One switch for the page (5yxn4w): Advanced adds the centre's latitude, longitude and altitude.
  const [advanced, setAdvanced] = useState(false);

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <RegionsHeader view="list" />
      <section className="space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <TableFilters
            setQueries={setQueries}
            setPagination={setPagination}
            queries={queries}
          />
          <div className="flex h-9 items-center gap-2 px-1">
            <Label htmlFor="regions-advanced">Advanced</Label>
            <Switch
              id="regions-advanced"
              checked={advanced}
              onCheckedChange={setAdvanced}
              data-regions-advanced=""
            />
          </div>
        </div>
        <div className="rounded-md border overflow-hidden">
          <RegionTable regions={data?.regions ?? []} onChanged={refresh} advanced={advanced} />
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
