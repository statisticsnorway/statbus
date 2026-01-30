"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState, useMemo } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useTimeContext } from '@/atoms/app-derived';
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh, isJwtExpiredError, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

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

  useGuardedEffect(() => {
    cache.clear();
  }, [cache], 'use-drill-down-data.tsx:clearCache');

  const fetcher = async (url: string) => {
    if (cache.has(url)) {
      return cache.get(url);
    }
    const response = await fetchWithAuthRefresh(url);
    
    // Check for JWT expiration in the response
    if (response.status === 401) {
      const text = await response.text();
      if (text.includes("JWT expired") || text.includes("PGRST301")) {
        throw new JwtExpiredError();
      }
      throw new Error(`Unauthorized: ${text}`);
    }
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    cache.set(url, data);
    return data;
  };

  const swrResponse = useSWRWithAuthRefresh<DrillDown>(
    `/api/reports?${urlSearchParams.toString()}`,
    fetcher,
    {
      keepPreviousData: true,
    },
    "useDrillDownData"
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
