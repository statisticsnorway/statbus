"use server";

import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Globe2 } from "lucide-react";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";

export const RegionCard = async () => {
  const client = await createPostgRESTSSRClient();

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
