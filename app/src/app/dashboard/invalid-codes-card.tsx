import { createClient } from "@/utils/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";

export const InvalidCodesCard = async () => {
  const client = createClient();
  console.log("client:");
  debugger;
  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .not("invalid_codes", "is", null)
    .neq("unit_type", "enterprise")
    .limit(0);

  return (
    <DashboardCard
      title="Units With Import Issues"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
