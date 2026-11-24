"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { ExactCount, useExactCount } from "@/components/exact-count";
import { useTimeFrame } from "@/atoms/app-derived";
import { useCallback } from "react";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";

export const StatisticalUnitCountCard = ({
  unitType,
  title,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly title: string;
}) => {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;

  // STATBUS-460: the card counts units that EXIST at valid_on by the canonical
  // rule (existence_from/existence_until, see lib/unit-existence.ts) and are
  // used for counting (status), which is exactly the Reports Units-over-time
  // chart's countable_count, so card and chart agree bar for bar. The card
  // counts for itself: an empty register answers 0.
  const countUnits = useCallback(async () => {
    const client = await getBrowserRestClient();
    return client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .eq("unit_type", unitType)
      .lte(EXISTENCE_FROM, validOn!)
      .gt(EXISTENCE_UNTIL, validOn!)
      .eq("used_for_counting", true)
      .limit(0);
  }, [unitType, validOn]);

  const { count, failed } = useExactCount(
    validOn ? `${unitType}-${validOn}` : null,
    countUnits
  );

  return (
    <DashboardCard
      title={title}
      icon={<StatisticalUnitIcon type={unitType} className="h-4" />}
      failed={failed}
    >
      <ExactCount count={count} failed={failed} />
    </DashboardCard>
  );
};
