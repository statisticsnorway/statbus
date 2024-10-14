import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Settings } from "lucide-react";

export const CustomActivityCategoryCard = async () => {
  const client = await createSupabaseSSRClient();

  const { count, error } = await client
    .from("activity_category_available_custom")
    .select("", { count: "exact" })
    .limit(0);

  return (
    <DashboardCard
      title="Custom Activity Category Codes"
      icon={<Settings className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
