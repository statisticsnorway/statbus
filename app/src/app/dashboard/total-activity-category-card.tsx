import { createClient } from "@/utils/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { BookText } from "lucide-react";

export const TotalActivityCategoryCard = async () => {
  const client = await createClient();

  const { count, error } = await client
    .from("activity_category_available")
    .select("", { count: "exact" })
    .limit(0);

  return (
    <DashboardCard
      title="All Activity Category Codes"
      icon={<BookText className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
