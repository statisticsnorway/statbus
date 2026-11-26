"use client";
import { useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { restClientAtom } from "@/atoms/rest-client";
import { RegionsHeader } from "./regions-header";
import { TableResultCount } from "@/components/table/table-result-count";
import TablePagination from "../../components/table/table-pagination";
import RegionTable from "./region-table";
import useRegion from "./use-region";
import TableFilters from "./region-table-filters";

export default function RegionPage() {
  const client = useAtomValue(restClientAtom);
  const { data, pagination, setPagination, queries, setQueries, refresh } = useRegion();
  // Whether any region has a centre. The page is simple until one has (owner 2026-11-26, 5yxn4w):
  // then it opens with Coordinates on, and the Map, drawn from those centres, is offered.
  const { data: anyCentre, mutate: recheckCentres } = useSWR(client ? ["regions:any-centre"] : null, async () => {
    const { data: rows, error } = await client!.from("region").select("id").not("center_latitude", "is", null).limit(1);
    if (error) throw error;
    return (rows ?? []).length > 0;
  });
  // The person's own choice; until they make one, the data decides.
  const [chosen, setChosen] = useState<boolean | null>(null);
  const showCoordinates = chosen ?? anyCentre ?? false;

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <RegionsHeader view="list" mapOffered={showCoordinates && anyCentre === true} />
      <section className="space-y-3">
        <TableFilters
          setQueries={setQueries}
          setPagination={setPagination}
          queries={queries}
          showCoordinates={showCoordinates}
          setShowCoordinates={setChosen}
        />
        <div className="rounded-md border overflow-hidden">
          <RegionTable
            regions={data?.regions ?? []}
            onChanged={() => {
              refresh();
              void recheckCentres();
            }}
            showCoordinates={showCoordinates}
          />
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
