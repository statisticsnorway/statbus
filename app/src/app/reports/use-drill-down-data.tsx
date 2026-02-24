"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState } from "react";
import { useTimeContext } from '@/atoms/app-derived';
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

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

  // Don't fetch until time context is ready — avoids a wasted ~5s request
  // with no valid_on that gets thrown away when selectedTimeContext arrives.
  const swrKey = selectedTimeContext?.valid_on
    ? `/api/reports?${urlSearchParams.toString()}`
    : null;

  const fetcher = async (url: string) => {
    const response = await fetchWithAuthRefresh(url);

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

    return response.json();
  };

  const swrResponse = useSWRWithAuthRefresh<DrillDown>(
    swrKey,
    fetcher,
    {
      keepPreviousData: true,
      revalidateOnFocus: false,
    },
    "useDrillDownData"
  );

  const drillDown = swrResponse.data;
  const isLoading = !swrResponse.data && !swrResponse.error;

  return {
    drillDown,
    isLoading,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};
