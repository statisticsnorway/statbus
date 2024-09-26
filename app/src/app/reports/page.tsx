import type { Metadata } from "next";
import ReportsPageClient from "./ReportsPageClient";

export const metadata: Metadata = {
  title: "Statbus | Reports",
};

export default function ReportsPage() {
  return <ReportsPageClient />;
}
