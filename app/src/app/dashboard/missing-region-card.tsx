"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { AlertTriangle } from "lucide-react";
import { useTimeContext } from '@/atoms/app';
import { useEffect, useState } from "react";
import { PostgrestError } from "@supabase/postgrest-js";

export const MissingRegionCard = () => {
  const { selectedTimeContext } = useTimeContext();

  const [data, setData] = useState<{ count: number | null; error: PostgrestError | null }>({ count: null, error: null });

  useEffect(() => {
    const fetchData = async (validOn: string) => {
      const client = await getBrowserRestClient();
      const { count, error } = await client
        .from("statistical_unit")
        .select("", { count: "exact" })
        .is("physical_region_path", null)
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
  }, [selectedTimeContext]);

  const { count, error } = data;

  return (
    <DashboardCard
      title="Units Missing Region"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};
