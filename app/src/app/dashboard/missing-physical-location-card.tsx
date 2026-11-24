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
export const MISSING_PHYSICAL_LOCATION_HREF = `/search?${QUALITY_CARD_UNIT_TYPE_PARAM}&physical_location=missing`;

// STATBUS-625: counts legal units and establishments that EXIST at the selected
// instant (lib/unit-existence.ts) and have no physical location then, e.g. after
// Remove took it away for part of their life. A location's country is required,
// so no physical_country_id means no physical location. The number matches the
// Statistical Units list the card links to (filter physical_location=missing).
const countMissingPhysicalLocation = async (validOn: string) => {
  const client = await getBrowserRestClient();
  return client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("physical_country_id", null)
    .in("unit_type", [...QUALITY_CARD_UNIT_TYPES])
    .lte(EXISTENCE_FROM, validOn)
    .gt(EXISTENCE_UNTIL, validOn)
    .limit(0);
};

export const MissingPhysicalLocationCard = () => {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const countUnits = useCallback(
    () => countMissingPhysicalLocation(validOn!),
    [validOn]
  );
  const { count, failed } = useExactCount(
    validOn ? `missing-physical-location-${validOn}` : null,
    countUnits
  );
  return (
    <DashboardCard
      title="Units Missing Physical Location"
      icon={<AlertTriangle className="h-4" />}
      failed={failed || (count ?? 0) > 0}
    >
      <ExactCount count={count} failed={failed} />
    </DashboardCard>
  );
};
