"use client";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";
import { useTimeContext } from "@/app/time-context";

export const InvalidCodesCard = async () => {
  const { selectedTimeContext } = useTimeContext();
  const client = await createSupabaseBrowserClientAsync();
  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .not("invalid_codes", "is", null)
    .neq("unit_type", "enterprise")
    .lt('valid_from', selectedTimeContext.valid_on)
    .gte('valid_to', selectedTimeContext.valid_on)
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
