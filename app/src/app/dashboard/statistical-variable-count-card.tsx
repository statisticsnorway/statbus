import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { BarChart3 } from "lucide-react";

export const StatisticalVariableCountCard = async () => {
  const client = await createPostgRESTSSRClient();

  const { count, error } = await client
    .from("stat_definition_active")
    .select("", { count: "exact" })
    .limit(0);

  return (
    <DashboardCard
      title="Statistical Variables"
      icon={<BarChart3 className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
