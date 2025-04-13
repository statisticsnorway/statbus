"use server";

import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Globe2 } from "lucide-react";
import { getServerClient } from "@/context/ClientStore";

export const RegionCard = async () => {
  const client = await getServerClient();

  const { count, error } = await client
    .from("region")
    .select("", { count: "exact" })
    .limit(0);

  return (
    <DashboardCard
      title="Region Hierarchy"
      icon={<Globe2 className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
