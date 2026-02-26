import type { Metadata } from "next";
import { Suspense } from "react";
import ReportsPageClient from "./ReportsPageClient";

export const metadata: Metadata = {
  title: "Reports Drilldown",
};

export default function ReportsDrilldownPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ReportsPageClient />
    </Suspense>
  );
}
