"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState } from "react";
import { useTimeContext } from "@/app/use-time-context";
import useSWR from "swr";

export const useDrillDownData = (initialDrillDown: DrillDown) => {
  const { selectedPeriod } = useTimeContext();
  const [region, setRegion] = useState<DrillDownPoint | null>(null);
  const [activityCategory, setActivityCategory] =
    useState<DrillDownPoint | null>(null);

  const urlSearchParams = new URLSearchParams();

  if (region?.path) {
    urlSearchParams.set("region_path", region?.path);
  }

  if (activityCategory?.path) {
    urlSearchParams.set("activity_category_path", activityCategory?.path);
  }

  if (selectedPeriod?.valid_on) {
    urlSearchParams.set("valid_on", selectedPeriod.valid_on);
  }

  const swrResponse = useSWR<DrillDown>(
    `/api/reports?${urlSearchParams}`,
    (url: string) => fetch(url).then((res) => res.json()),
    {
      fallbackData: initialDrillDown,
      keepPreviousData: true,
    }
  );

  return {
    drillDown: swrResponse.data,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
