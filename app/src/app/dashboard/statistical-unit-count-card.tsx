import { createClient } from "@/utils/supabase/server";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export const StatisticalUnitCountCard = async ({
  unitType,
  title,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly title: string;
}) => {
  const client = await createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .eq("unit_type", unitType)
    .limit(0);

  return (
    <DashboardCard
      title={title}
      icon={<StatisticalUnitIcon type={unitType} className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
