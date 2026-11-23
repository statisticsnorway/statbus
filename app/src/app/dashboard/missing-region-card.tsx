"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { EstimatedCount, useShownCount, useDataVersion } from "@/components/estimated-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useState, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";

// Counts domestic legal units and establishments that EXIST at the selected
// instant (lib/unit-existence.ts) and have a physical location but no region.
// A foreign unit has no region by design, and a unit without a physical
// location has no region either but is counted on the Units Missing Physical
// Location card, so each problem shows on one card (pkne34). The number
// matches the Statistical Units list the card links to (MISSING_REGION_HREF).
const countMissingRegion = async (
  validOn: string,
  count: "estimated" | "exact"
) => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count })
    .is("physical_region_path", null)
    .is("domestic", true)
    .not("physical_country_id", "is", null)
    .neq("unit_type", "enterprise")
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

/** The Statistical Units list with the same filters as the card's count. */
export const MISSING_REGION_HREF =
  "/search?unit_type=legal_unit,establishment&physical_region_path=null&domestic=true&physical_location=present";

export const MissingRegionCard = () => {
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
      countMissingRegion(validOn, "estimated").then(({ count, error }) =>
        setData({ count, error })
      );
    },
    [selectedTimeFrame, dataVersion],
    "MissingRegionCard:fetchData"
  );

  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeFrame?.valid_on) return null;
    const { count } = await countMissingRegion(
      selectedTimeFrame.valid_on,
      "exact"
    );
    return count;
  }, [selectedTimeFrame]);

  const { count, error } = data;
  const cacheKey = `missing-region-${selectedTimeFrame?.valid_on ?? "default"}`;
  const shownCount = useShownCount(cacheKey, count);
  return (
    <DashboardCard
      title="Units Missing Region"
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
