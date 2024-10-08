"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState, useMemo, useEffect } from "react";
import useSWR from "swr";
import { useTimeContext } from "../time-context";

export const useDrillDownData = () => {
  const { selectedTimeContext } = useTimeContext();
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

  if (selectedTimeContext?.valid_on) {
    urlSearchParams.set("valid_on", selectedTimeContext.valid_on);
  }

  const cache = useMemo(() => new Map<string, DrillDown>(), []);

  useEffect(() => {
    cache.clear();
  }, [cache]);

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
      keepPreviousData: true,
    }
  );

  // Use initial data when no parameters are present
  const drillDown = swrResponse.data;

  return {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
