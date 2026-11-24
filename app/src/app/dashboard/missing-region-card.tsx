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

// Counts domestic legal units and establishments that EXIST at the selected
// instant (lib/unit-existence.ts) and have a physical location but no region.
// A foreign unit has no region by design, and a unit without a physical
// location has no region either but is counted on the Units Missing Physical
// Location card, so each problem shows on one card (pkne34). The number
// matches the Statistical Units list the card links to (MISSING_REGION_HREF).
const countMissingRegion = async (validOn: string) => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("physical_region_path", null)
    .is("domestic", true)
    .not("physical_country_id", "is", null)
    .in("unit_type", [...QUALITY_CARD_UNIT_TYPES])
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

/** The Statistical Units list with the same filters as the card's count. */
export const MISSING_REGION_HREF = `/search?${QUALITY_CARD_UNIT_TYPE_PARAM}&physical_region_path=null&domestic=true&physical_location=present`;

export const MissingRegionCard = () => {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const countUnits = useCallback(() => countMissingRegion(validOn!), [validOn]);
  const { count, failed } = useExactCount(
    validOn ? `missing-region-${validOn}` : null,
    countUnits
  );
  return (
    <DashboardCard
      title="Units Missing Region"
      icon={<AlertTriangle className="h-4" />}
      failed={failed || (count ?? 0) > 0}
    >
      <ExactCount count={count} failed={failed} />
    </DashboardCard>
  );
};
