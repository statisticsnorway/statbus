"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { useTimeContext } from '@/atoms/app';
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";

export const StatisticalUnitCountCard = ({
  unitType,
  title,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly title: string;
}) => {
  const { selectedTimeContext } = useTimeContext();

  const [data, setData] = useState<{ count: number | null; error: PostgrestError | null }>({ count: null, error: null });

  useGuardedEffect(() => {
    const fetchData = async (validOn: string) => {
      const client = await getBrowserRestClient();
      const { count, error } = await client
        .from("statistical_unit")
        .select("", { count: "exact" })
        .eq("unit_type", unitType)
        .lte('valid_from', validOn)
        .gte('valid_to', validOn)
        .limit(0);

      return { count, error };
    };

    const fetchDataAsync = async () => {
      if (selectedTimeContext?.valid_on){
      const result = await fetchData(selectedTimeContext.valid_on);
      setData(result);
      }
    };

    fetchDataAsync();
  }, [selectedTimeContext, unitType], `StatisticalUnitCountCard:${unitType}:fetchData`);

  const { count, error } = data;

  return (
    <DashboardCard
      title={title}
      icon={<StatisticalUnitIcon type={unitType} className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};
