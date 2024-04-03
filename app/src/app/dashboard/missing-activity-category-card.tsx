import { createClient } from "@/lib/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";

export const MissingActivityCategoryCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("primary_activity_category_path", null)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Units Missing Activity Category"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
