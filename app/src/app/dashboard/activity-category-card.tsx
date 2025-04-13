import { getServerClient } from "@/context/ClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { ScrollText } from "lucide-react";

export const ActivityCategoryCard = async () => {
  const client = await getServerClient();

  const { data: settings, error } = await client
    .from("settings")
    .select("activity_category_standard(id,name)")
    .single();

  return (
    <DashboardCard
      title="Activity Category Standard"
      icon={<ScrollText className="h-4" />}
      text={settings?.activity_category_standard?.name ?? "-"}
      failed={!!error}
    />
  );
};
