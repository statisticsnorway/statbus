"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import {
  EstimatedCount,
  useShownCount,
  useDataVersion,
} from "@/components/estimated-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useState, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import {
  QUALITY_CARD_UNIT_TYPES,
  QUALITY_CARD_UNIT_TYPE_PARAM,
} from "@/app/dashboard/quality-card-unit-types";

/** The Statistical Units list with the same filters as the card's count. */
export const MISSING_PHYSICAL_LOCATION_HREF = `/search?${QUALITY_CARD_UNIT_TYPE_PARAM}&physical_location=missing`;

// STATBUS-625: counts legal units and establishments that EXIST at the selected
// instant (lib/unit-existence.ts) and have no physical location then, e.g. after
// Remove took it away for part of their life. A location's country is required,
// so no physical_country_id means no physical location. The number matches the
// Statistical Units list the card links to (filter physical_location=missing).
const countMissingPhysicalLocation = async (
  validOn: string,
  count: "estimated" | "exact"
) => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count })
    .is("physical_country_id", null)
    .in("unit_type", [...QUALITY_CARD_UNIT_TYPES])
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

export const MissingPhysicalLocationCard = () => {
  const { selectedTimeFrame } = useTimeFrame();
  // A new data version refetches the estimate (see useDataVersion).
  const dataVersion = useDataVersion();
  const [data, setData] = useState<{
    count: number | null;
    error: PostgrestError | null;
  }>({ count: null, error: null });

  useGuardedEffect(
    () => {
      const validOn = selectedTimeFrame?.valid_on;
      if (!validOn) return;
      countMissingPhysicalLocation(validOn, "estimated").then(
        ({ count, error }) => setData({ count, error })
      );
    },
    [selectedTimeFrame, dataVersion],
    "MissingPhysicalLocationCard:fetchData"
  );

  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeFrame?.valid_on) return null;
    const { count } = await countMissingPhysicalLocation(
      selectedTimeFrame.valid_on,
      "exact"
    );
    return count;
  }, [selectedTimeFrame]);

  const { count, error } = data;
  const cacheKey = `missing-physical-location-${selectedTimeFrame?.valid_on ?? "default"}`;
  const shownCount = useShownCount(cacheKey, count);
  return (
    <DashboardCard
      title="Units Missing Physical Location"
      icon={<AlertTriangle className="h-4" />}
      failed={!!error || (shownCount ?? 0) > 0}
    >
      <EstimatedCount
        estimatedCount={count}
        onGetExact={handleGetExact}
        cacheKey={cacheKey}
      />
    </DashboardCard>
  );
};
