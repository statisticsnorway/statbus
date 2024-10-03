import { createClient } from "@/utils/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Globe2 } from "lucide-react";

export const RegionCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("region")
    .select("", { count: "exact" })
    .limit(0);

  return (
    <DashboardCard
      title="Regions"
      icon={<Globe2 className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
