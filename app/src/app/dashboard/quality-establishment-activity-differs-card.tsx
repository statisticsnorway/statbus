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

// Quality check establishment_activity_differs (xz3jej): counts legal units that EXIST at the
// selected instant (lib/unit-existence.ts) and that the check lists. The inner embed of
// public.quality_establishment_activity_differs is the one the search adds for
// ?quality=establishment_activity_differs, so the number matches the list the card opens.
const QUALITY_EMBED = "quality_establishment_activity_differs!inner()";

export const QualityEstablishmentActivityDiffersCard = () => {
  const { selectedTimeFrame } = useTimeFrame();

  const [data, setData] = useState<{
    count: number | null;
    error: PostgrestError | null;
  }>({
    count: null,
    error: null,
  });

  const countLegalUnits = useCallback(
    async (validOn: string, count: "estimated" | "exact") => {
      const client = await getBrowserRestClient();
      return client
        .from("statistical_unit")
        .select(QUALITY_EMBED, { count })
        .eq("unit_type", "legal_unit")
        .lte(EXISTENCE_FROM, validOn)
        .gt(EXISTENCE_UNTIL, validOn)
        .limit(0);
    },
    []
  );

  useGuardedEffect(
    () => {
      const validOn = selectedTimeFrame?.valid_on;
      if (!validOn) return;
      countLegalUnits(validOn, "estimated").then(({ count, error }) =>
        setData({ count, error })
      );
    },
    [selectedTimeFrame, countLegalUnits],
    "QualityEstablishmentActivityDiffersCard:fetchData"
  );

  const { count, error } = data;

  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeFrame?.valid_on) return null;
    const { count: exactCount } = await countLegalUnits(
      selectedTimeFrame.valid_on,
      "exact"
    );
    return exactCount;
  }, [selectedTimeFrame, countLegalUnits]);

  return (
    <DashboardCard
      title="Establishment Activity Differs"
      description="Legal units whose primary establishment has another primary activity"
      icon={<AlertTriangle className="h-4" />}
      failed={!!error || (count ?? 0) > 0}
    >
      <EstimatedCount
        estimatedCount={count}
        onGetExact={handleGetExact}
        cacheKey={`quality-establishment-activity-differs-${selectedTimeFrame?.valid_on ?? "default"}`}
      />
    </DashboardCard>
  );
};
