"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { EstimatedCount } from "@/components/estimated-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useState, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";

// STATBUS-625: counts legal units and establishments that EXIST at the selected
// instant (lib/unit-existence.ts) and have no physical location then, e.g. after
// Remove took it away for part of their life. A location's country is required,
// so no physical_country_id means no physical location. The number matches the
// Statistical Units list the card links to (filter physical_location=missing).
const countMissingPhysicalLocation = async (validOn: string, count: "estimated" | "exact") => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count })
    .is("physical_country_id", null)
    .neq("unit_type", "enterprise")
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

export const MissingPhysicalLocationCard = () => {
  const { selectedTimeFrame } = useTimeFrame();
  const [data, setData] = useState<{ count: number | null; error: PostgrestError | null }>({ count: null, error: null });

  useGuardedEffect(
    () => {
      const validOn = selectedTimeFrame?.valid_on;
      if (!validOn) return;
      countMissingPhysicalLocation(validOn, "estimated").then(({ count, error }) => setData({ count, error }));
    },
    [selectedTimeFrame],
    "MissingPhysicalLocationCard:fetchData"
  );

  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeFrame?.valid_on) return null;
    const { count } = await countMissingPhysicalLocation(selectedTimeFrame.valid_on, "exact");
    return count;
  }, [selectedTimeFrame]);

  const { count, error } = data;
  return (
    <DashboardCard
      title="Units Missing Physical Location"
      icon={<AlertTriangle className="h-4" />}
      failed={!!error || (count ?? 0) > 0}
    >
      <EstimatedCount
        estimatedCount={count}
        onGetExact={handleGetExact}
        cacheKey={`missing-physical-location-${selectedTimeFrame?.valid_on ?? "default"}`}
      />
    </DashboardCard>
  );
};
