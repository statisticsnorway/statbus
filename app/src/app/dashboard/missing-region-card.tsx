import { createClient } from "@/lib/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";

export const MissingRegionCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("physical_region_path", null)
    .neq("unit_type", "enterprise")
    .limit(0);

  return (
    <DashboardCard
      title="Units Missing Region"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
