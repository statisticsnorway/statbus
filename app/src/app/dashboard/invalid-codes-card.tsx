"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";
import { useTimeContext } from "@/atoms/app-derived";
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";

export const InvalidCodesCard = () => {
  const { selectedTimeContext } = useTimeContext();

  const [data, setData] = useState<{ count: number | null; error: PostgrestError | null }>({ count: null, error: null });

  useGuardedEffect(() => {
    const fetchData = async (validOn: string) => {
      const client = await getBrowserRestClient();
      const { count, error } = await client
        .from("statistical_unit")
        .select("", { count: "exact" })
        .not("invalid_codes", "is", null)
        .neq("unit_type", "enterprise")
        .lte('valid_from', validOn)
        .gte('valid_to', validOn)
        .limit(0);

      return { count, error };
    };

    const fetchDataAsync = async () => {
      if (selectedTimeContext?.valid_on) {
        const result = await fetchData(selectedTimeContext.valid_on);
        setData(result);
      }
    };

    fetchDataAsync();
  }, [selectedTimeContext], 'InvalidCodesCard:fetchData');

  const { count, error } = data;

  return (
    <DashboardCard
      title="Units With Import Issues"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
