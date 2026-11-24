"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { ExactCount, useExactCount } from "@/components/exact-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useCallback } from "react";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import {
  QUALITY_CHECKS,
  type QualityCheck,
} from "@/app/search/filters/url-search-params";

/**
 * A Data quality card for a quality check on legal units (public.quality_<check>): it counts the
 * legal units that EXIST at the selected instant (lib/unit-existence.ts) and that the check lists,
 * through the inner embed the search adds for ?quality=<check>, so the number equals the list the
 * card opens (qualityCheckHref in url-search-params.ts).
 */
export const LegalUnitQualityCheckCard = ({
  check,
  title,
  description,
}: {
  readonly check: QualityCheck;
  readonly title: string;
  /** The full rule, shown when the pointer rests on the title; the check's label when omitted. */
  readonly description?: string;
}) => {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;

  const countLegalUnits = useCallback(async () => {
    const client = await getBrowserRestClient();
    return client
      .from("statistical_unit")
      .select(`quality_${check}!inner()`, { count: "exact" })
      .eq("unit_type", "legal_unit")
      .lte(EXISTENCE_FROM, validOn!)
      .gt(EXISTENCE_UNTIL, validOn!)
      .limit(0);
  }, [check, validOn]);

  const { count, failed } = useExactCount(
    validOn ? `quality-${check}-${validOn}` : null,
    countLegalUnits
  );

  return (
    <DashboardCard
      title={title}
      description={description ?? QUALITY_CHECKS[check].label}
      icon={<AlertTriangle className="h-4" />}
      failed={failed || (count ?? 0) > 0}
    >
      <ExactCount count={count} failed={failed} />
    </DashboardCard>
  );
};
