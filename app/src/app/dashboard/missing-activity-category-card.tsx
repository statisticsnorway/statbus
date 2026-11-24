"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { ExactCount, useExactCount } from "@/components/exact-count";
import { AlertTriangle } from "lucide-react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useCallback } from "react";
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import {
  QUALITY_CARD_UNIT_TYPES,
  QUALITY_CARD_UNIT_TYPE_PARAM,
} from "@/app/dashboard/quality-card-unit-types";

/** The Statistical Units list with the same filters as the card's count. */
export const MISSING_ACTIVITY_CATEGORY_HREF = `/search?${QUALITY_CARD_UNIT_TYPE_PARAM}&primary_activity_category_path=null`;

// STATBUS-460: counts legal units and establishments that EXIST at the selected
// instant (canonical rule, lib/unit-existence.ts) and lack a primary activity
// category, so the number matches what the Statistical Units list shows when clicked.
const countMissingActivityCategory = async (validOn: string) => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("primary_activity_category_path", null)
    .in("unit_type", [...QUALITY_CARD_UNIT_TYPES])
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

export const MissingActivityCategoryCard = () => {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const countUnits = useCallback(
    () => countMissingActivityCategory(validOn!),
    [validOn]
  );
  const { count, failed } = useExactCount(
    validOn ? `missing-activity-${validOn}` : null,
    countUnits
  );
  return (
    <DashboardCard
      title="Units Missing Activity Category"
      icon={<AlertTriangle className="h-4" />}
      failed={failed || (count ?? 0) > 0}
    >
      <ExactCount count={count} failed={failed} />
    </DashboardCard>
  );
};
