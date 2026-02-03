"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { EstimatedCount } from "@/components/estimated-count";
import { useTimeContext } from '@/atoms/app-derived';
import { useState, useCallback } from "react";
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
      // Use estimated count for fast loading
      const { count, error } = await client
        .from("statistical_unit")
        .select("", { count: "estimated" })
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

  // Callback to fetch exact count when user requests it
  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeContext?.valid_on) return null;
    const client = await getBrowserRestClient();
    const { count: exactCount } = await client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .eq("unit_type", unitType)
      .lte('valid_from', selectedTimeContext.valid_on)
      .gte('valid_to', selectedTimeContext.valid_on)
      .limit(0);
    return exactCount;
  }, [selectedTimeContext, unitType]);

  return (
    <DashboardCard
      title={title}
      icon={<StatisticalUnitIcon type={unitType} className="h-4" />}
      failed={!!error}
    >
      <EstimatedCount
        estimatedCount={count}
        onGetExact={handleGetExact}
        cacheKey={`${unitType}-${selectedTimeContext?.valid_on ?? 'default'}`}
      />
    </DashboardCard>
  );
};
