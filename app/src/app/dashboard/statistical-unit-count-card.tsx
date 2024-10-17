"use client";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";
import { useTimeContext } from "@/app/time-context";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export const StatisticalUnitCountCard = async ({
  unitType,
  title,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly title: string;
}) => {
  const { selectedTimeContext } = useTimeContext();
  const client = await createSupabaseBrowserClientAsync();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .eq("unit_type", unitType)
    .lt('valid_from', selectedTimeContext.valid_on)
    .gte('valid_to', selectedTimeContext.valid_on)
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
