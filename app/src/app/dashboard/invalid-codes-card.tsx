import { createClient } from "@/lib/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";

export const InvalidCodesCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .not("invalid_codes", "is", null)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Units With Import Issues"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
