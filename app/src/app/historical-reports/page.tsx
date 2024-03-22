import { createClient } from "@/lib/supabase/server";
import { HistoricalReportChart } from "./historical-report-chart";

export default async function HistoryPage() {
  const client = createClient();

  return (
    <main className="flex flex-col items-center justify-between px-2 py-8 md:py-24">
      <h1>History</h1>
      <HistoricalReportChart />
    </main>
  );
}
