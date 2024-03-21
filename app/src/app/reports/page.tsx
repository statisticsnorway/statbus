import { Metadata } from "next";
import StatBusChart from "@/app/reports/statbus-chart";
import { createClient } from "@/lib/supabase/server";
import { DrillDown } from "@/app/reports/types/drill-down";
import logger from "@/lib/logger";

export const metadata: Metadata = {
  title: "StatBus | Reports",
};

export default async function ReportsPage() {
  const client = createClient();
  const { data: drillDown, error } = await client
    .rpc("statistical_unit_facet_drilldown")
    .returns<DrillDown>();

  if (error) {
    logger.info(
      { error },
      "failed to fetch statistical unit facet drill down data"
    );
    return (
      <p className="p-24 text-center">
        Sorry! We failed to fetch statistical unit facet drill down data.
      </p>
    );
  }

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col px-2 py-8 md:py-24">
      <h1 className="mb-3 text-center text-2xl">StatBus Data Drilldown</h1>
      <p className="mb-12 text-center">
        Gain data insights by drilling through the bar charts below
      </p>
      <StatBusChart drillDown={drillDown} />
    </main>
  );
}
