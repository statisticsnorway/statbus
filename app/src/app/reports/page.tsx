import type { Metadata } from "next";
import ReportsPageClient from "./ReportsPageClient";
import { Suspense } from "react";

export const metadata: Metadata = {
  title: "Reports",
};

export default function ReportsPage({
}) {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ReportsPageClient />
    </Suspense>
  );
}
