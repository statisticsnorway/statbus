"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState, useMemo, useEffect } from "react";
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

  const cache = useMemo(() => new Map<string, DrillDown>(), []);

  useEffect(() => {
    cache.clear();
  }, []);

  const fetcher = async (url: string) => {
    if (cache.has(url)) {
      return cache.get(url);
    }
    const response = await fetch(url);
    const data = await response.json();
    cache.set(url, data);
    return data;
  };

  const swrResponse = useSWR<DrillDown>(
    `/api/reports?${urlSearchParams.toString()}`,
    fetcher,
    {
      fallbackData: initialDrillDown,
      keepPreviousData: true,
    }
  );

  // Use initial data when no parameters are present
  const drillDown = swrResponse.data || initialDrillDown;

  return {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
