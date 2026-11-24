"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import {
  EstimatedCount,
  useDataVersion,
  useShownCount,
} from "@/components/estimated-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useState, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { PostgrestError } from "@supabase/postgrest-js";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import {
  QUALITY_CHECKS,
  type QualityCheck,
} from "@/app/search/filters/url-search-params";

/**
 * A Data quality card for a quality check on legal units (public.quality_<check>): it counts the
 * legal units that EXIST at the selected instant (lib/unit-existence.ts) and that the check lists,
 * through the inner embed the search adds for ?quality=<check>, so the number equals the list the
 * card opens (qualityCheckHref).
 */
export function qualityCheckHref(check: QualityCheck): string {
  return `/search?unit_type=legal_unit&quality=${check}`;
}

export const LegalUnitQualityCheckCard = ({
  check,
  title,
}: {
  readonly check: QualityCheck;
  readonly title: string;
}) => {
  const { selectedTimeFrame } = useTimeFrame();
  const dataVersion = useDataVersion();
  const [data, setData] = useState<{
    count: number | null;
    error: PostgrestError | null;
  }>({ count: null, error: null });

  const countLegalUnits = useCallback(
    async (validOn: string, count: "estimated" | "exact") => {
      const client = await getBrowserRestClient();
      return client
        .from("statistical_unit")
        .select(`quality_${check}!inner()`, { count })
        .eq("unit_type", "legal_unit")
        .lte(EXISTENCE_FROM, validOn)
        .gt(EXISTENCE_UNTIL, validOn)
        .limit(0);
    },
    [check]
  );

  // A new data version refetches the estimate (see useDataVersion).
  useGuardedEffect(
    () => {
      const validOn = selectedTimeFrame?.valid_on;
      if (!validOn) return;
      countLegalUnits(validOn, "estimated").then(({ count, error }) =>
        setData({ count, error })
      );
    },
    [selectedTimeFrame, countLegalUnits, dataVersion],
    `LegalUnitQualityCheckCard:${check}:fetchData`
  );

  const handleGetExact = useCallback(async (): Promise<number | null> => {
    if (!selectedTimeFrame?.valid_on) return null;
    const { count } = await countLegalUnits(
      selectedTimeFrame.valid_on,
      "exact"
    );
    return count;
  }, [selectedTimeFrame, countLegalUnits]);

  const { count, error } = data;
  const cacheKey = `quality-${check}-${selectedTimeFrame?.valid_on ?? "default"}`;
  const shownCount = useShownCount(cacheKey, count);

  return (
    <DashboardCard
      title={title}
      description={QUALITY_CHECKS[check].label}
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
